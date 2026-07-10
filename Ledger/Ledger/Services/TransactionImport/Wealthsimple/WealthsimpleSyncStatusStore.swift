import Foundation

/// Non-secret sync metadata for the linked Wealthsimple connection (last successful sync, last
/// error, whether the session expired and needs a fresh login). Lives in UserDefaults, not the
/// Keychain -- only the session tokens are secret and those go in `WealthsimpleCredentialStore`.
@MainActor
struct WealthsimpleSyncStatusStore {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let lastSyncedAt = "wealthsimple.lastSyncedAt"
        static let lastError = "wealthsimple.lastError"
        static let needsReauth = "wealthsimple.needsReauth"
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
