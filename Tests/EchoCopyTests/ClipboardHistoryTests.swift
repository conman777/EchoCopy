import Foundation
import Security
import XCTest
@testable import EchoCopy

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    func testStartupArchivesLegacyHistoryAndStartsFreshWithoutKeychainAccess() throws {
        let suiteName = "EchoCopyTests.ClipboardHistory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storageKey = "history"
        let versionKey = "historyEncryptionVersion"
        let accessVersionKey = "\(versionKey).keychainAccessVersion"
        let provider = RetryableHistoryKeyProvider()
        let store = EncryptedHistoryStore(
            defaults: defaults,
            storageKey: storageKey,
            encryptionVersionKey: versionKey,
            keyProvider: provider
        )
        let expectedItem = ClipboardItem(content: "legacy history", contentType: .text)
        try store.save([expectedItem], maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        let originalPayload = try XCTUnwrap(defaults.data(forKey: storageKey))

        // Simulate an encrypted payload created before the app-owned v3
        // Keychain item was introduced.
        defaults.removeObject(forKey: accessVersionKey)
        provider.interactions.removeAll()

        let history = ClipboardHistory(historyStore: store)

        XCTAssertTrue(history.items.isEmpty)
        XCTAssertFalse(history.isPersistenceBlocked)
        XCTAssertFalse(history.canRetryHistoryUnlock)
        XCTAssertNil(history.persistenceError)
        XCTAssertTrue(provider.interactions.isEmpty)
        XCTAssertNil(defaults.data(forKey: storageKey))
        XCTAssertEqual(
            defaults.data(forKey: "\(storageKey).recoveryBackup"),
            originalPayload
        )

        history.addItem("fresh history", contentType: .text)
        history.flushPersistence()

        XCTAssertEqual(history.items.map(\.content), ["fresh history"])
        XCTAssertEqual(provider.interactions, [.nonInteractive])
        XCTAssertNotNil(defaults.data(forKey: storageKey))
        XCTAssertEqual(
            defaults.integer(forKey: accessVersionKey),
            EncryptedHistoryStore.currentKeychainAccessVersion
        )

        provider.interactions.removeAll()
        let restartedHistory = ClipboardHistory(historyStore: store)
        XCTAssertEqual(restartedHistory.items.map(\.content), ["fresh history"])
        XCTAssertEqual(provider.interactions, [.nonInteractive])
    }

    func testUnlockRetryRestoresEncryptedHistoryWithoutOverwritingPayload() throws {
        let suiteName = "EchoCopyTests.ClipboardHistory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storageKey = "history"
        let versionKey = "historyEncryptionVersion"
        let provider = RetryableHistoryKeyProvider()
        let store = EncryptedHistoryStore(
            defaults: defaults,
            storageKey: storageKey,
            encryptionVersionKey: versionKey,
            keyProvider: provider
        )
        let expectedItem = ClipboardItem(content: "preserved history", contentType: .text)
        try store.save([expectedItem], maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        let originalPayload = try XCTUnwrap(defaults.data(forKey: storageKey))

        provider.shouldFailNextLoad = true
        let history = ClipboardHistory(historyStore: store)

        XCTAssertTrue(history.items.isEmpty)
        XCTAssertTrue(history.isPersistenceBlocked)
        XCTAssertNotNil(history.persistenceError)
        XCTAssertEqual(defaults.data(forKey: storageKey), originalPayload)
        XCTAssertEqual(provider.interactions, [.nonInteractive, .nonInteractive])
        XCTAssertTrue(
            defaults.bool(forKey: "\(versionKey).keychainRepairRequired")
        )

        history.retryHistoryUnlock()

        XCTAssertEqual(history.items.map(\.content), [expectedItem.content])
        XCTAssertFalse(history.isPersistenceBlocked)
        XCTAssertNil(history.persistenceError)
        XCTAssertEqual(
            provider.interactions,
            [.nonInteractive, .nonInteractive, .userInitiated]
        )
        XCTAssertEqual(defaults.data(forKey: storageKey), originalPayload)
        XCTAssertFalse(
            defaults.bool(forKey: "\(versionKey).keychainRepairRequired")
        )
    }
}

private final class RetryableHistoryKeyProvider: HistoryKeyProviding {
    let keyData = Data(repeating: 0x3C, count: 32)
    var shouldFailNextLoad = false
    var interactions: [KeychainInteraction] = []

    func loadKeyData() throws -> Data? {
        try loadKeyData(interaction: .nonInteractive)
    }

    func loadKeyData(interaction: KeychainInteraction) throws -> Data? {
        interactions.append(interaction)
        if shouldFailNextLoad {
            shouldFailNextLoad = false
            throw EncryptedHistoryStoreError.keychain(errSecInteractionNotAllowed)
        }
        return keyData
    }

    func createKeyData() throws -> Data {
        keyData
    }
}
