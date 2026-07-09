import AuthenticationServices
import Foundation
import UIKit

/// Drives Plaid's Hosted Link flow via `ASWebAuthenticationSession`. Plaid presents its own
/// hosted UI (institution search → Wealthsimple login → account selection) at the
/// `hosted_link_url` returned by `/link/token/create`, then redirects to our `ledger://` custom
/// scheme (`completion_redirect_uri`) when the user finishes or cancels.
///
/// Unlike an OAuth handshake, the completion redirect itself carries no token -- it just signals
/// that the session is done. The caller then calls `/link/token/get` to retrieve the resulting
/// `public_token`. So this session's job is simply to wait for the redirect (or a user cancel).
@MainActor
final class PlaidConnectSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum ConnectError: Error {
        case cancelled
        case failedToStart
    }

    private var continuation: CheckedContinuation<Void, Error>?

    func connect(hostedLinkURL: URL, callbackScheme: String = "ledger") async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation

            let session = ASWebAuthenticationSession(url: hostedLinkURL, callbackURLScheme: callbackScheme) { [weak self] _, error in
                Task { @MainActor in
                    self?.handleCallback(error: error)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true

            if !session.start() {
                self.continuation = nil
                continuation.resume(throwing: ConnectError.failedToStart)
            }
        }
    }

    private func handleCallback(error: Error?) {
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                continuation.resume(throwing: ConnectError.cancelled)
            } else {
                continuation.resume(throwing: error)
            }
            return
        }

        // Any successful redirect back to our scheme means the Hosted Link session finished;
        // the resulting public_token is fetched separately via /link/token/get.
        continuation.resume(returning: ())
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
