import AuthenticationServices
import Foundation
import UIKit

/// Drives SnapTrade's hosted Connection Portal via `ASWebAuthenticationSession` (Apple's
/// recommended replacement for a bare SFSafariViewController + manual URL-scheme handling).
/// See https://docs.snaptrade.com/docs/implement-connection-portal -- the portal redirects
/// back to our `ledger://` custom scheme with `status=SUCCESS&connection_id=...` on success,
/// or `status=ERROR&error_code=...` on failure.
@MainActor
final class SnapTradeConnectSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum ConnectError: Error {
        case cancelled
        case invalidCallback
        case connectionFailed(String)
    }

    private var continuation: CheckedContinuation<String, Error>?

    @discardableResult
    func connect(portalURL: URL, callbackScheme: String = "ledger") async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let session = ASWebAuthenticationSession(url: portalURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.handleCallback(callbackURL: callbackURL, error: error)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true

            if !session.start() {
                self.continuation = nil
                continuation.resume(throwing: ConnectError.invalidCallback)
            }
        }
    }

    private func handleCallback(callbackURL: URL?, error: Error?) {
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

        guard let callbackURL,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            continuation.resume(throwing: ConnectError.invalidCallback)
            return
        }

        let queryItems = components.queryItems ?? []
        let status = queryItems.first { $0.name == "status" }?.value
        let connectionId = queryItems.first { $0.name == "connection_id" }?.value
            ?? queryItems.first { $0.name == "authorizationId" }?.value

        if status == "SUCCESS", let connectionId {
            continuation.resume(returning: connectionId)
        } else {
            let errorCode = queryItems.first { $0.name == "error_code" }?.value ?? status ?? "unknown"
            continuation.resume(throwing: ConnectError.connectionFailed(errorCode))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
