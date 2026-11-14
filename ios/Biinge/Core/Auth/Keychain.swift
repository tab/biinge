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

/// The Keychain calls behind the auth tokens, the Jellyfin connection and the Jellyfin device ID (tests pass a fake, so they never touch the user's real Keychain items)
protocol KeychainStore {
    func read(_ key: KeychainKey) -> String?
    @discardableResult
    func save(_ value: String, for key: KeychainKey) -> Bool
    func delete(_ key: KeychainKey)
}

/// A thin Security-framework wrapper for storing auth tokens (it stores and reads nothing in a test run)
struct Keychain: KeychainStore, Sendable {
    // the tests run hosted in the app, whose launch would otherwise read and delete the user's real items
    private static let isTestRun = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Replaces the key's value and returns whether the write went through
    @discardableResult
    func save(_ value: String, for key: KeychainKey) -> Bool {
        guard !Self.isTestRun else { return false }
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
        guard !Self.isTestRun else { return nil }
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
        guard !Self.isTestRun else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
