import Foundation
import Testing
@testable import Biinge

/// An in-memory Keychain, as a real item prompts for a password on an unsigned Mac test build
private final class KeychainStub: KeychainStore {
    var items: [KeychainKey: String] = [:]
    var refusesWrites = false

    func read(_ key: KeychainKey) -> String? { items[key] }

    func save(_ value: String, for key: KeychainKey) -> Bool {
        guard !refusesWrites else { return false }
        items[key] = value
        return true
    }
}

@MainActor
@Suite(.serialized)
struct JellyfinDeviceIDTests {
    private static let suiteName = "JellyfinDeviceIDTests"
    // a domain of its own, as the tests run hosted in the app and share its standard defaults
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    private let keychain = KeychainStub()

    init() {
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    @Test func aFreshInstallCreatesAnIDAndStoresIt() {
        let id = JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults)

        #expect(UUID(uuidString: id) != nil)
        #expect(keychain.items[.jellyfinDeviceID] == id)
        #expect(defaults.string(forKey: "jellyfinDeviceID") == nil)
    }

    @Test func theKeychainValueWins() {
        keychain.items[.jellyfinDeviceID] = "keychain-id"
        defaults.set("defaults-id", forKey: "jellyfinDeviceID")

        #expect(JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults) == "keychain-id")
        #expect(keychain.items[.jellyfinDeviceID] == "keychain-id")
    }

    @Test func theMigrationMovesTheOldValueUnchanged() {
        defaults.set("old-id", forKey: "jellyfinDeviceID")

        #expect(JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults) == "old-id")
        #expect(keychain.items[.jellyfinDeviceID] == "old-id")
        #expect(defaults.string(forKey: "jellyfinDeviceID") == nil)
    }

    @Test func aSecondRunKeepsTheSameID() {
        let first = JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults)

        #expect(JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults) == first)
    }

    @Test func aFailedKeychainWriteKeepsTheUserDefaultsValue() {
        keychain.refusesWrites = true
        defaults.set("old-id", forKey: "jellyfinDeviceID")

        #expect(JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults) == "old-id")
        #expect(defaults.string(forKey: "jellyfinDeviceID") == "old-id")

        // the next launch's write goes through, and the ID moves unchanged
        keychain.refusesWrites = false
        #expect(JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults) == "old-id")
        #expect(keychain.items[.jellyfinDeviceID] == "old-id")
        #expect(defaults.string(forKey: "jellyfinDeviceID") == nil)
    }

    @Test func aNewIDStaysTheSameWhileTheKeychainRefusesWrites() {
        keychain.refusesWrites = true

        let first = JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults)

        #expect(JellyfinConnection.storedDeviceID(keychain: keychain, defaults: defaults) == first)
    }
}
