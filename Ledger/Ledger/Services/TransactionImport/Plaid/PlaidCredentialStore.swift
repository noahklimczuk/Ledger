import Foundation

/// Which Plaid environment the API keys belong to. Real Wealthsimple data requires `production`;
/// `sandbox` returns fake test institutions and is only useful for wiring the flow up.
enum PlaidEnvironment: String, CaseIterable, Sendable, Identifiable {
    case sandbox
    case development
    case production

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sandbox: "Sandbox"
        case .development: "Development"
        case .production: "Production"
        }
    }

    var baseURL: URL {
        switch self {
        case .sandbox: URL(string: "https://sandbox.plaid.com")!
        case .development: URL(string: "https://development.plaid.com")!
        case .production: URL(string: "https://production.plaid.com")!
        }
    }
}

/// Sendable snapshot of everything needed to call an authenticated (post-link) Plaid endpoint.
struct PlaidCredentials: Sendable {
    let clientId: String
    let secret: String
    let environment: PlaidEnvironment
    let clientUserId: String
    let accessToken: String
}

/// Keychain-backed storage for Plaid API credentials and the per-Item `access_token` returned
/// after a successful Link. Nothing here is ever written to UserDefaults, Info.plist, or
/// source-controlled config -- `clientId`/`secret` come from the user's own Plaid dashboard
/// (dashboard.plaid.com) and are entered once in More > Connect Wealthsimple.
@MainActor
final class PlaidCredentialStore {
    private enum Key {
        static let clientId = "plaid.clientId"
        static let secret = "plaid.secret"
        static let environment = "plaid.environment"
        static let clientUserId = "plaid.clientUserId"
        static let accessToken = "plaid.accessToken"
        static let itemId = "plaid.itemId"
    }

    var clientId: String? {
        get { KeychainService.getString(forKey: Key.clientId) }
        set { setOrDelete(newValue, forKey: Key.clientId) }
    }

    var secret: String? {
        get { KeychainService.getString(forKey: Key.secret) }
        set { setOrDelete(newValue, forKey: Key.secret) }
    }

    var environment: PlaidEnvironment {
        get { KeychainService.getString(forKey: Key.environment).flatMap(PlaidEnvironment.init) ?? .production }
        set { try? KeychainService.set(newValue.rawValue, forKey: Key.environment) }
    }

    /// Plaid's identifier for this single local app user. Any stable string works; a UUID is
    /// generated on first read and reused after that.
    var clientUserId: String {
        if let existing = KeychainService.getString(forKey: Key.clientUserId) {
            return existing
        }
        let generated = UUID().uuidString
        try? KeychainService.set(generated, forKey: Key.clientUserId)
        return generated
    }

    var accessToken: String? {
        get { KeychainService.getString(forKey: Key.accessToken) }
        set { setOrDelete(newValue, forKey: Key.accessToken) }
    }

    var itemId: String? {
        get { KeychainService.getString(forKey: Key.itemId) }
        set { setOrDelete(newValue, forKey: Key.itemId) }
    }

    var hasAPICredentials: Bool { clientId != nil && secret != nil }
    var isConnected: Bool { accessToken != nil }

    /// A fully-populated snapshot for authenticated calls, or nil if the Link flow
    /// (which produces the access token) hasn't completed yet.
    var snapshot: PlaidCredentials? {
        guard let clientId, let secret, let accessToken else { return nil }
        return PlaidCredentials(
            clientId: clientId,
            secret: secret,
            environment: environment,
            clientUserId: clientUserId,
            accessToken: accessToken
        )
    }

    func disconnect() {
        accessToken = nil
        itemId = nil
    }

    private func setOrDelete(_ value: String?, forKey key: String) {
        if let value {
            try? KeychainService.set(value, forKey: key)
        } else {
            KeychainService.delete(forKey: key)
        }
    }
}
