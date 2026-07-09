import Foundation

/// Sendable snapshot of everything needed to call the SnapTrade API for one request.
struct SnapTradeCredentials: Sendable {
    let clientId: String
    let consumerKey: String
    let userId: String
    let userSecret: String
}

/// Keychain-backed storage for SnapTrade API credentials and the per-user secret returned
/// after registration. Nothing here is ever written to UserDefaults, Info.plist, or
/// source-controlled config -- clientId and consumerKey come from the user's own SnapTrade
/// developer dashboard (snaptrade.com) and are entered once in Settings > Integrations.
@MainActor
final class SnapTradeCredentialStore {
    private enum Key {
        static let clientId = "snaptrade.clientId"
        static let consumerKey = "snaptrade.consumerKey"
        static let userId = "snaptrade.userId"
        static let userSecret = "snaptrade.userSecret"
    }

    var clientId: String? {
        get { KeychainService.getString(forKey: Key.clientId) }
        set { setOrDelete(newValue, forKey: Key.clientId) }
    }

    var consumerKey: String? {
        get { KeychainService.getString(forKey: Key.consumerKey) }
        set { setOrDelete(newValue, forKey: Key.consumerKey) }
    }

    /// SnapTrade's identifier for this single local app user. Any stable string works; a
    /// UUID is generated on first read and reused after that.
    var userId: String {
        if let existing = KeychainService.getString(forKey: Key.userId) {
            return existing
        }
        let generated = UUID().uuidString
        try? KeychainService.set(generated, forKey: Key.userId)
        return generated
    }

    var userSecret: String? {
        get { KeychainService.getString(forKey: Key.userSecret) }
        set { setOrDelete(newValue, forKey: Key.userSecret) }
    }

    var hasAPICredentials: Bool { clientId != nil && consumerKey != nil }
    var isConnected: Bool { userSecret != nil }

    /// A fully-populated snapshot for the API client, or nil if setup (API credentials
    /// and/or SnapTrade user registration) isn't complete yet.
    var snapshot: SnapTradeCredentials? {
        guard let clientId, let consumerKey, let userSecret else { return nil }
        return SnapTradeCredentials(clientId: clientId, consumerKey: consumerKey, userId: userId, userSecret: userSecret)
    }

    func disconnect() {
        userSecret = nil
    }

    private func setOrDelete(_ value: String?, forKey key: String) {
        if let value {
            try? KeychainService.set(value, forKey: key)
        } else {
            KeychainService.delete(forKey: key)
        }
    }
}
