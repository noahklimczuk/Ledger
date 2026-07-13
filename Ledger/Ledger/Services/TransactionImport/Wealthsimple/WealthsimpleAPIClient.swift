import Foundation

/// Minimal hand-rolled client for Wealthsimple's own production API -- the same endpoints the
/// Wealthsimple web app calls, no third-party SDK and no aggregator in between. This is the free
/// replacement for the Plaid path: the user signs in with their Wealthsimple email/password (and
/// 2FA), and the app reads their Cash account activity directly.
///
/// Auth is OAuth password grant against `api.production.wealthsimple.com`; data is read from the
/// GraphQL endpoint at `my.wealthsimple.com/graphql`. Both need two identifiers Wealthsimple hands
/// out on the login page -- a device id (`wssdi` cookie) and the web app's OAuth `client_id`
/// (embedded in its JS bundle) -- which `bootstrap()` scrapes once per login.
struct WealthsimpleAPIClient: Sendable {
    enum ClientError: Error, LocalizedError {
        case bootstrapFailed(String)
        case otpRequired
        case loginFailed(String)
        /// The refresh token is dead; the user must sign in again.
        case reauthRequired
        case server(status: Int, message: String?)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .bootstrapFailed(let detail):
                "Couldn't reach Wealthsimple's login (\(detail)). Try again in a moment."
            case .otpRequired:
                "Enter the 2-step verification code from your authenticator or text message."
            case .loginFailed(let detail):
                detail
            case .reauthRequired:
                "Wealthsimple needs you to sign in again to keep syncing."
            case .server(let status, let message):
                "Wealthsimple error \(status): \(message ?? "no details")."
            case .invalidResponse:
                "Wealthsimple returned an unexpected response."
            }
        }
    }

    private static let oauthBaseURL = URL(string: "https://api.production.wealthsimple.com/v1/oauth/v2")!
    private static let graphQLURL = URL(string: "https://my.wealthsimple.com/graphql")!
    private static let loginPageURL = URL(string: "https://my.wealthsimple.com/app/login")!
    private static let graphQLVersion = "12"
    private static let wealthsimpleClient = "@wealthsimple/wealthsimple"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Bootstrap

    private struct Bootstrap { let deviceId: String; let clientId: String }

    /// Fetches the login page (for the `wssdi` device-id cookie and the app JS URL) and then the
    /// JS bundle (for the production `client_id`). Both can rotate, so they're read live rather
    /// than hard-coded.
    private func bootstrap() async throws -> Bootstrap {
        let (pageData, _) = try await get(Self.loginPageURL, headers: [:])
        let html = String(decoding: pageData, as: UTF8.self)

        guard let deviceId = Self.cookieValue("wssdi", for: Self.loginPageURL) else {
            throw ClientError.bootstrapFailed("no device id")
        }
        guard let appJSPath = Self.firstCapture(in: html, pattern: #"<script[^>]*src="([^"]+/app-[a-f0-9]+\.js)""#),
              let appJSURL = URL(string: appJSPath.hasPrefix("http") ? appJSPath : "https://my.wealthsimple.com" + appJSPath) else {
            throw ClientError.bootstrapFailed("no app bundle")
        }

        let (jsData, _) = try await get(appJSURL, headers: [:])
        let js = String(decoding: jsData, as: UTF8.self)
        guard let clientId = Self.firstCapture(in: js, pattern: #""production"[^}]*?clientId:"([a-f0-9]+)""#) else {
            throw ClientError.bootstrapFailed("no client id")
        }

        return Bootstrap(deviceId: deviceId, clientId: clientId)
    }

    // MARK: - Login

    /// Logs in with the user's Wealthsimple credentials. Throws `.otpRequired` when 2FA is needed
    /// and no `otp` was supplied -- the caller should collect the code and call again.
    func logIn(email: String, password: String, otp: String?) async throws -> WealthsimpleSession {
        let boot = try await bootstrap()
        let sessionId = UUID().uuidString

        var headers = [
            "x-wealthsimple-client": Self.wealthsimpleClient,
            "x-ws-profile": "undefined",
            "x-ws-session-id": sessionId,
            "x-ws-device-id": boot.deviceId
        ]
        if let otp {
            headers["x-wealthsimple-otp"] = "\(otp);remember=true"
        }

        let body: [String: Any] = [
            "grant_type": "password",
            "username": email,
            "password": password,
            "skip_provision": "true",
            "scope": "invest.read trade.read tax.read",
            "client_id": boot.clientId,
            "otp_claim": NSNull()
        ]

        let response = try await postForToken(
            Self.oauthBaseURL.appendingPathComponent("token"),
            body: body,
            headers: headers
        )

        if response.error == "invalid_grant", otp == nil {
            throw ClientError.otpRequired
        }
        if let error = response.error {
            throw ClientError.loginFailed(loginFailureMessage(for: error))
        }
        guard let accessToken = response.accessToken, let refreshToken = response.refreshToken else {
            throw ClientError.invalidResponse
        }

        return WealthsimpleSession(
            clientId: boot.clientId,
            accessToken: accessToken,
            refreshToken: refreshToken,
            sessionId: sessionId,
            deviceId: boot.deviceId,
            identityId: nil
        )
    }

    /// Mints a fresh access token from the refresh token. Throws `.reauthRequired` when the refresh
    /// token is no longer valid (the user must log in again).
    func refreshedSession(_ session: WealthsimpleSession) async throws -> WealthsimpleSession {
        let headers = [
            "x-wealthsimple-client": Self.wealthsimpleClient,
            "x-ws-profile": "invest",
            "x-ws-session-id": session.sessionId,
            "x-ws-device-id": session.deviceId
        ]
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": session.refreshToken,
            "client_id": session.clientId
        ]

        let response = try await postForToken(Self.oauthBaseURL.appendingPathComponent("token"), body: body, headers: headers)

        guard let accessToken = response.accessToken, let refreshToken = response.refreshToken else {
            throw ClientError.reauthRequired
        }
        var updated = session
        updated.accessToken = accessToken
        updated.refreshToken = refreshToken
        return updated
    }

    /// The identity the session's tokens belong to (needed to scope account queries).
    func identityId(for session: WealthsimpleSession) async throws -> String {
        let headers = [
            "x-wealthsimple-client": Self.wealthsimpleClient,
            "x-ws-session-id": session.sessionId,
            "x-ws-device-id": session.deviceId
        ]
        let (data, http) = try await get(
            Self.oauthBaseURL.appendingPathComponent("token/info"),
            headers: headers,
            bearer: session.accessToken
        )
        guard http.statusCode == 200 else { throw ClientError.server(status: http.statusCode, message: nil) }
        let info = try decoder.decode(WealthsimpleDTO.TokenInfoResponse.self, from: data)
        guard let id = info.identityCanonicalId else { throw ClientError.invalidResponse }
        return id
    }

    // MARK: - GraphQL

    func query<T: Decodable>(
        _ type: T.Type,
        operationName: String,
        query: String,
        variables: [String: Any],
        session: WealthsimpleSession
    ) async throws -> T {
        let headers = [
            "x-ws-api-version": Self.graphQLVersion,
            "x-ws-profile": "trade",
            "x-ws-locale": "en-CA",
            "x-platform-os": "web",
            "x-ws-session-id": session.sessionId,
            "x-ws-device-id": session.deviceId
        ]
        let body: [String: Any] = [
            "operationName": operationName,
            "query": query,
            "variables": variables
        ]
        let envelope: WealthsimpleDTO.GraphQLResponse<T> = try await postJSON(
            Self.graphQLURL,
            body: body,
            headers: headers,
            bearer: session.accessToken
        )
        if let message = envelope.errors?.first?.message {
            // "Not Authorized." here means the access token lapsed mid-sync.
            if message == "Not Authorized." { throw ClientError.reauthRequired }
            throw ClientError.loginFailed(message)
        }
        guard let data = envelope.data else { throw ClientError.invalidResponse }
        return data
    }

    // MARK: - Request plumbing

    /// The OAuth token endpoint returns its `{"error": ...}` body with a 4xx status (e.g. a 401
    /// for "2FA required"), so unlike a normal call we decode the body regardless of status and
    /// let the caller interpret the `error` field.
    private func postForToken(
        _ url: URL,
        body: [String: Any],
        headers: [String: String]
    ) async throws -> WealthsimpleDTO.TokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if let decoded = try? decoder.decode(WealthsimpleDTO.TokenResponse.self, from: data) {
            return decoded
        }
        throw ClientError.server(status: http.statusCode, message: String(data: data, encoding: .utf8))
    }

    private func postJSON<Response: Decodable>(
        _ url: URL,
        body: [String: Any],
        headers: [String: String],
        bearer: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.server(status: http.statusCode, message: String(data: data, encoding: .utf8))
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ClientError.invalidResponse
        }
    }

    private func get(_ url: URL, headers: [String: String], bearer: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        return (data, http)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Turns raw OAuth error codes into something a person can act on.
    private func loginFailureMessage(for error: String) -> String {
        switch error {
        case "invalid_grant": "Wrong email, password, or 2-step code. Check them and try again."
        default: "Wealthsimple login failed (\(error))."
        }
    }

    // MARK: - Helpers

    private static func cookieValue(_ name: String, for url: URL) -> String? {
        HTTPCookieStorage.shared.cookies(for: url)?.first { $0.name == name }?.value
    }

    /// First capture group of `pattern` in `text`, or nil.
    static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}
