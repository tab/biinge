import Foundation
import Security

enum KeychainKey: String {
    case accessToken = "com.biinge.accessToken"
    case refreshToken = "com.biinge.refreshToken"
    case jellyfinServer = "com.biinge.jellyfinServer"
    case jellyfinUserID = "com.biinge.jellyfinUserID"
    case jellyfinToken = "com.biinge.jellyfinToken"
    case jellyfinUserName = "com.biinge.jellyfinUserName"
    case jellyfinServerName = "com.biinge.jellyfinServerName"
    case jellyfinDeviceID = "com.biinge.jellyfinDeviceID"
}

/// The Keychain calls behind the Jellyfin device ID (tests pass a fake, as a real item prompts for a password on an unsigned Mac build)
protocol KeychainStore {
    func read(_ key: KeychainKey) -> String?
    func save(_ value: String, for key: KeychainKey) -> Bool
}

/// A thin Security-framework wrapper for storing auth tokens
struct Keychain: KeychainStore, Sendable {
    /// Replaces the key's value and returns whether the write went through
    @discardableResult
    func save(_ value: String, for key: KeychainKey) -> Bool {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: Data(value.utf8),
            // Keep tokens on this device only — never migrated to a restored backup
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func read(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
