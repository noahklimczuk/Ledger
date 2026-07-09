import Foundation

/// Minimal hand-rolled REST client for the SnapTrade API (no third-party SDK dependency, since
/// that can't be verified to resolve/compile from this machine). Base URL and endpoint paths
/// per https://docs.snaptrade.com/reference -- reconfirm exact paths/fields against the live
/// docs once real API credentials are available.
struct SnapTradeAPIClient: Sendable {
    enum ClientError: Error, LocalizedError {
        case invalidResponse
        case server(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "SnapTrade returned an unexpected response."
            case .server(let status, let body): "SnapTrade error \(status): \(body)"
            }
        }
    }

    private let baseURL = URL(string: "https://api.snaptrade.com/api/v1")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func registerUser(clientId: String, consumerKey: String, userId: String) async throws -> SnapTradeDTO.RegisterUserResponse {
        try await post(path: "/snapTrade/registerUser", clientId: clientId, consumerKey: consumerKey, body: ["userId": userId])
    }

    func generateLoginURL(
        credentials: SnapTradeCredentials,
        customRedirect: String,
        connectionType: String = "read"
    ) async throws -> SnapTradeDTO.LoginResponse {
        let body: [String: Any] = [
            "userId": credentials.userId,
            "userSecret": credentials.userSecret,
            "customRedirect": customRedirect,
            "connectionType": connectionType
        ]
        return try await post(path: "/snapTrade/login", clientId: credentials.clientId, consumerKey: credentials.consumerKey, body: body)
    }

    func listAccounts(credentials: SnapTradeCredentials) async throws -> [SnapTradeDTO.Account] {
        try await get(path: "/accounts", credentials: credentials, extraQuery: [:])
    }

    func listActivities(accountId: String, since: Date?, credentials: SnapTradeCredentials) async throws -> [SnapTradeDTO.Activity] {
        var query: [String: String] = [:]
        if let since {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            query["startDate"] = formatter.string(from: since)
        }
        return try await get(path: "/accounts/\(accountId)/activities", credentials: credentials, extraQuery: query)
    }

    // MARK: - Request plumbing

    private func get<Response: Decodable>(
        path: String,
        credentials: SnapTradeCredentials,
        extraQuery: [String: String]
    ) async throws -> Response {
        var query = extraQuery
        query["userId"] = credentials.userId
        query["userSecret"] = credentials.userSecret
        return try await send(
            method: "GET",
            path: path,
            clientId: credentials.clientId,
            consumerKey: credentials.consumerKey,
            extraQuery: query,
            jsonBody: nil
        )
    }

    private func post<Response: Decodable>(
        path: String,
        clientId: String,
        consumerKey: String,
        body: [String: Any]
    ) async throws -> Response {
        let jsonBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(method: "POST", path: path, clientId: clientId, consumerKey: consumerKey, extraQuery: [:], jsonBody: jsonBody)
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        clientId: String,
        consumerKey: String,
        extraQuery: [String: String],
        jsonBody: Data?
    ) async throws -> Response {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        var queryItems = [
            URLQueryItem(name: "clientId", value: clientId),
            URLQueryItem(name: "timestamp", value: timestamp)
        ]
        for (key, value) in extraQuery {
            queryItems.append(URLQueryItem(name: key, value: value))
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        guard let url = components.url, let queryString = components.percentEncodedQuery else {
            throw ClientError.invalidResponse
        }

        // Sign the exact query string that will be sent, so encoding/ordering can never
        // drift between what we sign and what the server receives.
        let signature = SnapTradeSigning.signature(
            consumerKey: consumerKey,
            path: "/api/v1" + path,
            query: queryString,
            jsonBody: jsonBody
        )

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(signature, forHTTPHeaderField: "Signature")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jsonBody {
            request.httpBody = jsonBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.server(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
