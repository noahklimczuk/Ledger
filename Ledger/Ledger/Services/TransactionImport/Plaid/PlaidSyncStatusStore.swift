import Foundation

/// Non-secret sync metadata for the linked Plaid connection (last successful sync, last error,
/// whether Plaid is asking the user to re-authenticate). Lives in UserDefaults, not the Keychain —
/// only secrets (client id/secret/access token) go in the Keychain.
@MainActor
struct PlaidSyncStatusStore {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let lastSyncedAt = "plaid.lastSyncedAt"
        static let lastError = "plaid.lastError"
        static let needsReauth = "plaid.needsReauth"
    }

    var lastSyncedAt: Date? {
        get { defaults.object(forKey: Key.lastSyncedAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastSyncedAt) }
    }

    var lastError: String? {
        get { defaults.string(forKey: Key.lastError) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastError) }
    }

    var needsReauth: Bool {
        get { defaults.bool(forKey: Key.needsReauth) }
        nonmutating set { defaults.set(newValue, forKey: Key.needsReauth) }
    }

    func recordSuccess() {
        lastSyncedAt = Date()
        lastError = nil
        needsReauth = false
    }

    func recordFailure(_ message: String) {
        lastError = message
    }

    func recordNeedsReauth() {
        needsReauth = true
        lastError = "Wealthsimple needs you to sign in again to keep syncing."
    }

    func clear() {
        defaults.removeObject(forKey: Key.lastSyncedAt)
        defaults.removeObject(forKey: Key.lastError)
        defaults.removeObject(forKey: Key.needsReauth)
    }
}
