import Foundation
import Security
import XCTest
@testable import EchoCopy

final class EncryptedHistoryStoreTests: XCTestCase {
    func testLiveStyleFileStorageMigratesEncryptedDefaultsPayload() throws {
        let context = makeContext()
        defer { context.cleanup() }

        let item = ClipboardItem(content: "file-backed history", contentType: .text)
        try context.store.save(
            [item],
            maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes
        )
        let encryptedDefaultsPayload = try XCTUnwrap(
            context.defaults.data(forKey: context.storageKey)
        )

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoCopyFileStoreTests-\(UUID().uuidString)")
        let payloadFileURL = directoryURL.appendingPathComponent("history.enc")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileStore = EncryptedHistoryStore(
            defaults: context.defaults,
            storageKey: context.storageKey,
            encryptionVersionKey: context.versionKey,
            payloadFileURL: payloadFileURL,
            keyProvider: context.keyProvider
        )

        let loaded = try XCTUnwrap(
            fileStore.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        )

        XCTAssertEqual(loaded.map(\.id), [item.id])
        XCTAssertNil(context.defaults.data(forKey: context.storageKey))
        XCTAssertEqual(try Data(contentsOf: payloadFileURL), encryptedDefaultsPayload)

        try fileStore.save(
            [ClipboardItem(content: "updated", contentType: .text)],
            maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes
        )
        XCTAssertNil(context.defaults.data(forKey: context.storageKey))
        XCTAssertTrue(
            try Data(contentsOf: payloadFileURL).starts(
                with: EncryptedHistoryStore.envelopeMagic
            )
        )
    }

    func testPlaintextMigrationNeverWritesPlaintextToHistoryFile() throws {
        let context = makeContext()
        defer { context.cleanup() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoCopyMigrationTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.enc")
        let item = ClipboardItem(content: "legacy private text")
        context.defaults.set(try JSONEncoder().encode([item]), forKey: context.storageKey)
        context.keyProvider.onCreate = {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                           "Plaintext must not reach the history file before encryption")
        }
        let store = EncryptedHistoryStore(
            defaults: context.defaults, storageKey: context.storageKey,
            encryptionVersionKey: context.versionKey, payloadFileURL: file,
            keyProvider: context.keyProvider
        )
        XCTAssertEqual(try store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)?.first?.content,
                       item.content)
        XCTAssertNil(context.defaults.data(forKey: context.storageKey))
        let payload = try Data(contentsOf: file)
        XCTAssertTrue(payload.starts(with: EncryptedHistoryStore.envelopeMagic))
        XCTAssertNil(payload.range(of: Data(item.content.utf8)))
    }

    func testExistingStoragePermissionsAreRepairedOnSaveAndLoad() throws {
        let context = makeContext()
        defer { context.cleanup() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoCopyPermissionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.enc")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        let store = EncryptedHistoryStore(
            defaults: context.defaults, storageKey: context.storageKey,
            encryptionVersionKey: context.versionKey, payloadFileURL: file,
            keyProvider: context.keyProvider
        )
        let item = ClipboardItem(content: "private permission test")
        try store.save([item], maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        func assertPrivatePermissions() throws {
            let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
            XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        try assertPrivatePermissions()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertEqual(try store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)?.first?.id,
                       item.id)
        try assertPrivatePermissions()
    }

    func testEverySaveUsesFreshCiphertextAndProtectsImageAndMetadata() throws {
        let context = makeContext()
        defer { context.cleanup() }
        let item = ClipboardItem(
            content: Data("synthetic image bytes".utf8).base64EncodedString(),
            contentType: .image, isPinned: true, filename: "private-screenshot.png",
            rtfContent: Data("synthetic rich text".utf8).base64EncodedString()
        )
        try context.store.save([item], maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        let first = try XCTUnwrap(context.defaults.data(forKey: context.storageKey))
        try context.store.save([item], maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        let second = try XCTUnwrap(context.defaults.data(forKey: context.storageKey))
        XCTAssertNotEqual(first, second)
        for value in [item.content, item.filename!, item.rtfContent!, item.id.uuidString] {
            XCTAssertNil(second.range(of: Data(value.utf8)))
        }
        let loaded = try XCTUnwrap(context.store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)?.first)
        XCTAssertEqual(loaded.content, item.content)
        XCTAssertEqual(loaded.filename, item.filename)
        XCTAssertEqual(loaded.rtfContent, item.rtfContent)
        XCTAssertEqual(loaded.isPinned, item.isPinned)
        XCTAssertEqual(loaded.timestamp, item.timestamp)
    }

    func testEncryptedHistoryRoundTripsWithoutPersistingPlaintext() throws {
        let context = makeContext()
        defer { context.cleanup() }

        let secret = "sensitive clipboard value"
        let item = ClipboardItem(content: secret, contentType: .text)

        try context.store.save([item], maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)

        let persisted = try XCTUnwrap(context.defaults.data(forKey: context.storageKey))
        XCTAssertTrue(persisted.starts(with: EncryptedHistoryStore.envelopeMagic))
        XCTAssertNil(persisted.range(of: Data(secret.utf8)))
        XCTAssertEqual(context.defaults.integer(forKey: context.versionKey), 1)

        let loaded = try XCTUnwrap(
            context.store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        )
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
        XCTAssertEqual(loaded[0].content, secret)
        XCTAssertEqual(loaded[0].contentType, .text)
    }

    func testTamperedCiphertextIsRejected() throws {
        let context = makeContext()
        defer { context.cleanup() }

        try context.store.save(
            [ClipboardItem(content: "authenticated", contentType: .text)],
            maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes
        )

        var persisted = try XCTUnwrap(context.defaults.data(forKey: context.storageKey))
        persisted[persisted.index(before: persisted.endIndex)] ^= 0x01
        context.defaults.set(persisted, forKey: context.storageKey)

        XCTAssertThrowsError(
            try context.store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        ) { error in
            guard case EncryptedHistoryStoreError.authenticationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMissingKeyDoesNotOverwriteEncryptedHistory() throws {
        let context = makeContext()
        defer { context.cleanup() }

        try context.store.save(
            [ClipboardItem(content: "preserve ciphertext", contentType: .text)],
            maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes
        )
        let original = try XCTUnwrap(context.defaults.data(forKey: context.storageKey))
        let storeWithoutKey = EncryptedHistoryStore(
            defaults: context.defaults,
            storageKey: context.storageKey,
            encryptionVersionKey: context.versionKey,
            keyProvider: TestHistoryKeyProvider()
        )

        XCTAssertThrowsError(
            try storeWithoutKey.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        ) { error in
            guard case EncryptedHistoryStoreError.missingKey = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(context.defaults.data(forKey: context.storageKey), original)
    }

    func testOversizedEncryptedHistoryIsPreserved() throws {
        let context = makeContext()
        defer { context.cleanup() }

        var encryptedPayload = EncryptedHistoryStore.envelopeMagic
        encryptedPayload.append(Data(repeating: 0xA5, count: 129))
        context.defaults.set(encryptedPayload, forKey: context.storageKey)
        context.defaults.set(1, forKey: context.versionKey)

        XCTAssertThrowsError(
            try context.store.load(maximumPlaintextBytes: 64)
        ) { error in
            guard case EncryptedHistoryStoreError.oversizedPayload = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(context.defaults.data(forKey: context.storageKey), encryptedPayload)
        XCTAssertEqual(context.defaults.integer(forKey: context.versionKey), 1)
    }

    func testLegacyPlaintextIsMigratedImmediately() throws {
        let context = makeContext()
        defer { context.cleanup() }

        let secret = "legacy clipboard value"
        let legacy = try JSONEncoder().encode([ClipboardItem(content: secret, contentType: .text)])
        context.defaults.set(legacy, forKey: context.storageKey)

        let loaded = try XCTUnwrap(
            context.store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        )
        XCTAssertEqual(loaded.first?.content, secret)

        let migrated = try XCTUnwrap(context.defaults.data(forKey: context.storageKey))
        XCTAssertTrue(migrated.starts(with: EncryptedHistoryStore.envelopeMagic))
        XCTAssertNil(migrated.range(of: Data(secret.utf8)))
        XCTAssertEqual(context.defaults.integer(forKey: context.versionKey), 1)
    }

    func testPlaintextDowngradeIsRejectedAfterMigration() throws {
        let context = makeContext()
        defer { context.cleanup() }

        let plaintext = try JSONEncoder().encode([
            ClipboardItem(content: "downgrade attempt", contentType: .text)
        ])
        context.defaults.set(plaintext, forKey: context.storageKey)
        context.defaults.set(1, forKey: context.versionKey)

        XCTAssertThrowsError(
            try context.store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        ) { error in
            guard case EncryptedHistoryStoreError.plaintextDowngrade = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertNil(context.defaults.data(forKey: context.storageKey))
    }

    func testFailedLegacyMigrationRemovesPlaintext() throws {
        let context = makeContext(keyProvider: TestHistoryKeyProvider(failCreation: true))
        defer { context.cleanup() }

        let legacy = try JSONEncoder().encode([
            ClipboardItem(content: "must not remain plaintext", contentType: .text)
        ])
        context.defaults.set(legacy, forKey: context.storageKey)

        XCTAssertThrowsError(
            try context.store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        )
        XCTAssertNil(context.defaults.data(forKey: context.storageKey))
        XCTAssertEqual(context.defaults.integer(forKey: context.versionKey), 1)
    }

    func testKeychainProviderCreatesAndReloadsKey() throws {
        let service = "com.conman777.echocopy.tests.\(UUID().uuidString)"
        let provider = KeychainHistoryKeyProvider(service: service)
        defer { deleteKeychainItems(service: service) }

        XCTAssertNil(try provider.loadKeyData())
        let created = try provider.createKeyData()
        XCTAssertEqual(created.count, 32)
        XCTAssertEqual(try provider.loadKeyData(), created)
        XCTAssertEqual(try provider.createKeyData(), created)

        let reloadedProvider = KeychainHistoryKeyProvider(service: service)
        XCTAssertEqual(try reloadedProvider.loadKeyData(), created)
    }

    func testLegacyKeychainKeyIsMigratedToCurrentAccount() throws {
        let service = "com.conman777.echocopy.tests.\(UUID().uuidString)"
        let legacyKeyData = Data(repeating: 0x7B, count: 32)
        defer { deleteKeychainItems(service: service) }

        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: KeychainHistoryKeyProvider.legacyAccount,
            kSecValueData as String: legacyKeyData
        ]
        XCTAssertEqual(SecItemAdd(legacyQuery as CFDictionary, nil), errSecSuccess)

        let provider = KeychainHistoryKeyProvider(service: service)
        XCTAssertNil(try provider.loadKeyData(interaction: .nonInteractive))
        XCTAssertEqual(
            try provider.loadKeyData(interaction: .userInitiated),
            legacyKeyData
        )

        let currentQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: KeychainHistoryKeyProvider.account,
            kSecReturnData as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        var result: CFTypeRef?
        XCTAssertEqual(
            SecItemCopyMatching(currentQuery as CFDictionary, &result),
            errSecSuccess
        )
        XCTAssertEqual(result as? Data, legacyKeyData)
    }

    func testAuthorizedKeyIsCachedForTheAppSession() throws {
        let service = "com.conman777.echocopy.tests.\(UUID().uuidString)"
        let provider = KeychainHistoryKeyProvider(service: service)
        defer { deleteKeychainItems(service: service) }

        let created = try provider.createKeyData()
        let providerCopyUsedByBackgroundPersistence = provider
        deleteKeychainItems(service: service)

        XCTAssertEqual(
            try providerCopyUsedByBackgroundPersistence.loadKeyData(),
            created
        )
    }

    func testOnlyAuthorizationErrorsOfferKeychainRepair() {
        XCTAssertTrue(
            EncryptedHistoryStoreError
                .keychain(errSecInteractionNotAllowed)
                .requiresKeychainUnlock
        )
        XCTAssertTrue(
            EncryptedHistoryStoreError
                .keychain(errSecAuthFailed)
                .requiresKeychainUnlock
        )
        XCTAssertFalse(
            EncryptedHistoryStoreError
                .keychain(errSecParam)
                .requiresKeychainUnlock
        )
        XCTAssertFalse(EncryptedHistoryStoreError.missingKey.requiresKeychainUnlock)
    }

    private func makeContext(
        keyProvider: TestHistoryKeyProvider = TestHistoryKeyProvider()
    ) -> TestStoreContext {
        let suiteName = "EchoCopyTests.EncryptedHistoryStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let storageKey = "history"
        let versionKey = "historyEncryptionVersion"
        let store = EncryptedHistoryStore(
            defaults: defaults,
            storageKey: storageKey,
            encryptionVersionKey: versionKey,
            keyProvider: keyProvider
        )

        return TestStoreContext(
            suiteName: suiteName,
            defaults: defaults,
            storageKey: storageKey,
            versionKey: versionKey,
            keyProvider: keyProvider,
            store: store
        )
    }

    private func deleteKeychainItems(service: String) {
        for account in [
            KeychainHistoryKeyProvider.account,
            KeychainHistoryKeyProvider.previousAccount,
            KeychainHistoryKeyProvider.legacyAccount
        ] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

private final class TestHistoryKeyProvider: HistoryKeyProviding {
    private var keyData: Data?
    private let failCreation: Bool
    var onCreate: (() -> Void)?

    init(keyData: Data? = nil, failCreation: Bool = false) {
        self.keyData = keyData
        self.failCreation = failCreation
    }

    func loadKeyData() throws -> Data? {
        keyData
    }

    func createKeyData() throws -> Data {
        onCreate?()
        if failCreation {
            throw TestKeyProviderError.creationFailed
        }

        let created = Data(repeating: 0xA5, count: 32)
        keyData = created
        return created
    }
}

private enum TestKeyProviderError: Error {
    case creationFailed
}

private struct TestStoreContext {
    let suiteName: String
    let defaults: UserDefaults
    let storageKey: String
    let versionKey: String
    let keyProvider: TestHistoryKeyProvider
    let store: EncryptedHistoryStore

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
