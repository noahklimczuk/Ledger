import Foundation
import Security

/// Thin wrapper around the Keychain Services API. Used for anything secret that must
/// survive app restarts without ever touching UserDefaults or plaintext files: Plaid
/// API credentials, the per-Item access token, etc.
enum KeychainService {
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
        case dataConversionFailed
    }

    private static let defaultService = "com.noah.Ledger"

    static func set(_ value: String, forKey key: String, service: String = defaultService) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataConversionFailed }
        try setData(data, forKey: key, service: service)
    }

    static func setData(_ data: Data, forKey key: String, service: String = defaultService) throws {
        let query = baseQuery(key: key, service: service)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
        } else if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func getString(forKey key: String, service: String = defaultService) -> String? {
        guard let data = getData(forKey: key, service: service) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func getData(forKey key: String, service: String = defaultService) -> Data? {
        var query = baseQuery(key: key, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(forKey key: String, service: String = defaultService) {
        SecItemDelete(baseQuery(key: key, service: service) as CFDictionary)
    }

    private static func baseQuery(key: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
