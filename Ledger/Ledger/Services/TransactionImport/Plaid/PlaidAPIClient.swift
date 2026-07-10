import Foundation

/// Minimal hand-rolled REST client for the Plaid API (no third-party SDK dependency, to keep the
/// project buildable without package resolution).
///
/// Plaid auth needs no request signing: `client_id` and `secret`
/// are sent in the JSON body of every request, over HTTPS, to the environment-specific host
/// (`sandbox`/`development`/`production`). See https://plaid.com/docs/api.
struct PlaidAPIClient: Sendable {
    enum ClientError: Error, LocalizedError {
        case invalidResponse
        case server(status: Int, code: String?, message: String?)
        case missingLinkURL
        case noConnectionCompleted
        case exchangeFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Plaid returned an unexpected response."
            case .server(let status, let code, let message):
                "Plaid error \(status)\(code.map { " (\($0))" } ?? ""): \(message ?? "no details")"
            case .missingLinkURL:
                "Plaid did not return a Hosted Link URL. Check that Hosted Link is enabled for your account."
            case .noConnectionCompleted:
                "No account connection was completed in Plaid Link."
            case .exchangeFailed:
                "Plaid did not return an access token."
            }
        }
    }

    private let session: URLSession
    private let dateOnlyFormatter: DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateOnlyFormatter = formatter
    }

    // MARK: - Link lifecycle

    /// Creates a Hosted Link token. `completionRedirectURI` is the custom-scheme URL Plaid
    /// redirects to when the user finishes (or cancels) the flow, closing the auth session.
    /// Creates a Hosted Link token. Pass `accessToken` to open Link in **update mode** to
    /// re-authenticate an existing Item (Plaid requires `products` be omitted in that case);
    /// otherwise a fresh connection is created.
    func createLinkToken(
        clientId: String,
        secret: String,
        environment: PlaidEnvironment,
        clientUserId: String,
        completionRedirectURI: String,
        accessToken: String? = nil
    ) async throws -> PlaidDTO.LinkTokenCreateResponse {
        var body: [String: Any] = [
            "client_id": clientId,
            "secret": secret,
            "client_name": "Ledger",
            "language": "en",
            "country_codes": ["CA"],
            "user": ["client_user_id": clientUserId],
            "hosted_link": ["completion_redirect_uri": completionRedirectURI]
        ]
        if let accessToken {
            body["access_token"] = accessToken
        } else {
            body["products"] = ["transactions"]
        }
        return try await post(environment: environment, path: "/link/token/create", body: body)
    }

    /// After the Hosted Link session completes, retrieves the `public_token` produced by the
    /// connection so it can be exchanged for a long-lived access token.
    func linkTokenResults(
        clientId: String,
        secret: String,
        environment: PlaidEnvironment,
        linkToken: String
    ) async throws -> PlaidDTO.LinkTokenGetResponse {
        let body: [String: Any] = [
            "client_id": clientId,
            "secret": secret,
            "link_token": linkToken
        ]
        return try await post(environment: environment, path: "/link/token/get", body: body)
    }

    func exchangePublicToken(
        clientId: String,
        secret: String,
        environment: PlaidEnvironment,
        publicToken: String
    ) async throws -> PlaidDTO.ExchangeResponse {
        let body: [String: Any] = [
            "client_id": clientId,
            "secret": secret,
            "public_token": publicToken
        ]
        return try await post(environment: environment, path: "/item/public_token/exchange", body: body)
    }

    // MARK: - Data

    func accounts(credentials: PlaidCredentials) async throws -> PlaidDTO.AccountsResponse {
        let body: [String: Any] = [
            "client_id": credentials.clientId,
            "secret": credentials.secret,
            "access_token": credentials.accessToken
        ]
        return try await post(environment: credentials.environment, path: "/accounts/balance/get", body: body)
    }

    func transactions(
        credentials: PlaidCredentials,
        startDate: Date,
        endDate: Date,
        offset: Int,
        count: Int
    ) async throws -> PlaidDTO.TransactionsResponse {
        let body: [String: Any] = [
            "client_id": credentials.clientId,
            "secret": credentials.secret,
            "access_token": credentials.accessToken,
            "start_date": dateOnlyFormatter.string(from: startDate),
            "end_date": dateOnlyFormatter.string(from: endDate),
            "options": ["count": count, "offset": offset]
        ]
        return try await post(environment: credentials.environment, path: "/transactions/get", body: body)
    }

    /// Asks Plaid to pull fresh data from the institution *now* instead of waiting for Plaid's own
    /// periodic refresh (which can lag hours behind). The extraction runs asynchronously on Plaid's
    /// side — a follow-up `/transactions/get` shortly after picks up whatever completed.
    @discardableResult
    func refreshTransactions(credentials: PlaidCredentials) async throws -> PlaidDTO.RefreshResponse {
        let body: [String: Any] = [
            "client_id": credentials.clientId,
            "secret": credentials.secret,
            "access_token": credentials.accessToken
        ]
        return try await post(environment: credentials.environment, path: "/transactions/refresh", body: body)
    }

    // MARK: - Request plumbing

    private func post<Response: Decodable>(
        environment: PlaidEnvironment,
        path: String,
        body: [String: Any]
    ) async throws -> Response {
        let url = environment.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? decoder.decode(PlaidDTO.ErrorResponse.self, from: data)
            throw ClientError.server(
                status: httpResponse.statusCode,
                code: error?.errorCode,
                message: error?.displayMessage ?? error?.errorMessage
            )
        }

        return try decoder.decode(Response.self, from: data)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
