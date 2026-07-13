import Foundation

/// Keychain-backed storage for the Wealthsimple `WealthsimpleSession` (OAuth tokens + device/
/// session ids). Serialized as one JSON blob under a single Keychain key.
///
/// Unlike the old Plaid flow there are no API keys to enter -- the only secret is the session that
/// falls out of the user's own login, and it lives in the Keychain only (never UserDefaults,
/// Info.plist, or source control).
@MainActor
final class WealthsimpleCredentialStore {
    private enum Key {
        static let session = "wealthsimple.session"
    }

    var session: WealthsimpleSession? {
        get {
            guard let data = KeychainService.getData(forKey: Key.session) else { return nil }
            return try? JSONDecoder().decode(WealthsimpleSession.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                try? KeychainService.setData(data, forKey: Key.session)
            } else {
                KeychainService.delete(forKey: Key.session)
            }
        }
    }

    var isConnected: Bool { session != nil }

    func disconnect() {
        session = nil
    }
}
