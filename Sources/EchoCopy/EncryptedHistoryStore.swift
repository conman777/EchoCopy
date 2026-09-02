import CryptoKit
import Foundation
import LocalAuthentication
import Security

protocol HistoryKeyProviding {
    func loadKeyData() throws -> Data?
    func loadKeyData(interaction: KeychainInteraction) throws -> Data?
    func createKeyData() throws -> Data
}

enum KeychainInteraction: Equatable {
    case nonInteractive
    case userInitiated
}

extension HistoryKeyProviding {
    /// Test and non-Keychain providers do not need a separate interaction
    /// policy. The live Keychain provider overrides this to control whether
    /// macOS authentication UI may appear.
    func loadKeyData(interaction: KeychainInteraction) throws -> Data? {
        try loadKeyData()
    }
}

enum EncryptedHistoryStoreError: Error {
    case authenticationFailed
    case decodingFailed
    case encodingFailed
    case invalidKeyMaterial
    case keychain(OSStatus)
    case missingKey
    case oversizedPayload
    case plaintextDowngrade
}

extension EncryptedHistoryStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Clipboard history failed authentication."
        case .decodingFailed:
            return "Clipboard history could not be decoded."
        case .encodingFailed:
            return "Clipboard history could not be encrypted."
        case .invalidKeyMaterial:
            return "The clipboard history encryption key is invalid."
        case .keychain(let status):
            return "Keychain returned status \(status)."
        case .missingKey:
            return "The clipboard history encryption key is missing."
        case .oversizedPayload:
            return "Clipboard history exceeds the secure storage limit."
        case .plaintextDowngrade:
            return "Unencrypted clipboard history was rejected after migration."
        }
    }
}

extension EncryptedHistoryStoreError {
    var requiresKeychainUnlock: Bool {
        switch self {
        case .keychain(let status):
            return status == errSecInteractionNotAllowed
                || status == errSecAuthFailed
                || status == errSecUserCanceled
        case .authenticationFailed, .decodingFailed, .encodingFailed,
             .invalidKeyMaterial, .missingKey, .oversizedPayload,
             .plaintextDowngrade:
            return false
        }
    }
}

/// Keeps a successfully authorized history key in memory for the lifetime of
/// the app. The encrypted history store is copied into its background
/// persistence coordinator, so this cache deliberately has reference semantics.
private final class HistoryKeyMemoryCache {
    private let lock = NSLock()
    private var keyData: Data?

    func load() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return keyData
    }

    func store(_ keyData: Data) {
        lock.lock()
        self.keyData = keyData
        lock.unlock()
    }
}

struct KeychainHistoryKeyProvider: HistoryKeyProviding {
    /// Version 3 is intentionally isolated from every legacy item. Automatic
    /// operations query only this account, so Security never evaluates an old
    /// ACL and can never present its password dialog. Legacy accounts are read
    /// only from an explicitly user-initiated recovery flow.
    static let account = "history-encryption-key-v3"
    static let previousAccount = "history-encryption-key-v2"
    static let legacyAccount = "history-encryption-key-v1"
    private let service: String
    private let memoryCache: HistoryKeyMemoryCache

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "com.yourcompany.echocopy").clipboard-history"
    ) {
        self.service = service
        self.memoryCache = HistoryKeyMemoryCache()
    }

    func loadKeyData() throws -> Data? {
        try loadKeyData(interaction: .nonInteractive)
    }

    func loadKeyData(interaction: KeychainInteraction) throws -> Data? {
        if let cachedKeyData = memoryCache.load() {
            return cachedKeyData
        }

        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = interaction == .nonInteractive
        if interaction == .userInitiated {
            authenticationContext.localizedReason = "Unlock EchoCopy's encrypted clipboard history."
        }

        if let currentKeyData = try loadKeyData(
            account: Self.account,
            interaction: interaction,
            authenticationContext: authenticationContext
        ) {
            memoryCache.store(currentKeyData)
            return currentKeyData
        }

        guard interaction == .userInitiated else {
            return nil
        }

        for legacyAccount in [Self.previousAccount, Self.legacyAccount] {
            guard let legacyKeyData = try loadKeyData(
                account: legacyAccount,
                interaction: interaction,
                authenticationContext: authenticationContext
            ) else {
                continue
            }

            let migratedKeyData = try addCurrentKeyData(
                legacyKeyData,
                interaction: interaction
            )
            memoryCache.store(migratedKeyData)
            return migratedKeyData
        }

        return nil
    }

    func createKeyData() throws -> Data {
        if let existingKey = try loadKeyData(interaction: .nonInteractive) {
            return existingKey
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let storedKeyData = try addCurrentKeyData(
            keyData,
            interaction: .nonInteractive
        )
        memoryCache.store(storedKeyData)
        return storedKeyData
    }

    private func loadKeyData(
        account: String,
        interaction: KeychainInteraction,
        authenticationContext: LAContext
    ) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authenticationContext
        ]

        var authenticationQuery = query
        if interaction == .nonInteractive {
            // UISkip is the only mode that reliably prevents legacy Keychain
            // items from presenting authentication UI during background/startup
            // work. User-initiated queries omit this key, using Security's
            // default interactive behavior.
            authenticationQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(authenticationQuery as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let keyData = result as? Data, keyData.count == 32 else {
                throw EncryptedHistoryStoreError.invalidKeyMaterial
            }
            return keyData
        case errSecItemNotFound:
            return nil
        default:
            throw EncryptedHistoryStoreError.keychain(status)
        }
    }

    private func addCurrentKeyData(
        _ keyData: Data,
        interaction: KeychainInteraction
    ) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrLabel as String: "EchoCopy Clipboard History Encryption Key",
            // The file-based Keychain's default ACL trusts the signed app that
            // creates the item. Versioning the item is what repairs stale ACLs
            // left behind by older, differently signed development builds.
            kSecValueData as String: keyData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let authenticationContext = LAContext()
            authenticationContext.interactionNotAllowed = interaction == .nonInteractive
            if interaction == .userInitiated {
                authenticationContext.localizedReason = "Unlock EchoCopy's encrypted clipboard history."
            }

            if let racedKey = try loadKeyData(
                account: Self.account,
                interaction: interaction,
                authenticationContext: authenticationContext
            ) {
                return racedKey
            }
        }
        guard status == errSecSuccess else {
            throw EncryptedHistoryStoreError.keychain(status)
        }

        return keyData
    }
}

struct EncryptedHistoryStore {
    static let envelopeMagic = Data([0x45, 0x43, 0x48, 0x31]) // "ECH1"
    static let currentEncryptionVersion = 1
    static let currentKeychainAccessVersion = 3
    private static let maximumEnvelopeOverhead = 64

    private let defaults: UserDefaults
    private let storageKey: String
    private let encryptionVersionKey: String
    private let keychainAccessVersionKey: String
    private let keychainRepairRequiredKey: String
    private let recoveryBackupKey: String
    private let recoveryBackupEncryptionVersionKey: String
    private let keyProvider: any HistoryKeyProviding
    private let payloadFileURL: URL?

    init(
        defaults: UserDefaults,
        storageKey: String,
        encryptionVersionKey: String,
        keychainAccessVersionKey: String? = nil,
        keychainRepairRequiredKey: String? = nil,
        recoveryBackupKey: String? = nil,
        recoveryBackupEncryptionVersionKey: String? = nil,
        payloadFileURL: URL? = nil,
        keyProvider: any HistoryKeyProviding
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.encryptionVersionKey = encryptionVersionKey
        self.keychainAccessVersionKey = keychainAccessVersionKey
            ?? "\(encryptionVersionKey).keychainAccessVersion"
        self.keychainRepairRequiredKey = keychainRepairRequiredKey
            ?? "\(encryptionVersionKey).keychainRepairRequired"
        self.recoveryBackupKey = recoveryBackupKey
            ?? "\(storageKey).recoveryBackup"
        self.recoveryBackupEncryptionVersionKey = recoveryBackupEncryptionVersionKey
            ?? "\(encryptionVersionKey).recoveryBackup"
        self.payloadFileURL = payloadFileURL
        self.keyProvider = keyProvider
    }

    /// Legacy file-based Keychain lookups can display authentication UI even
    /// when a query asks Security not to. Never touch such an item during
    /// startup until a user explicitly chooses the repair action. A successful
    /// version-2 save or load records that the fresh app-owned item is safe for
    /// later noninteractive startup reads.
    var requiresUserInitiatedKeychainRepair: Bool {
        guard hasStoredPayload else { return false }

        return defaults.bool(forKey: keychainRepairRequiredKey)
            || defaults.integer(forKey: keychainAccessVersionKey)
                < Self.currentKeychainAccessVersion
    }

    func recordKeychainRepairRequired() {
        defaults.set(true, forKey: keychainRepairRequiredKey)
    }

    /// Moves an unreadable legacy payload out of the active history slot before
    /// starting a clean v3 history. The backup remains untouched and can be
    /// recovered manually later, while normal clipboard capture is immediately
    /// usable without consulting any legacy Keychain ACL.
    @discardableResult
    func archiveLegacyHistoryAndStartFresh() -> Bool {
        guard let payload = try? readStoredPayload() else {
            defaults.removeObject(forKey: keychainRepairRequiredKey)
            defaults.removeObject(forKey: keychainAccessVersionKey)
            return false
        }

        if defaults.data(forKey: recoveryBackupKey) == nil,
           payload.starts(with: Self.envelopeMagic) {
            defaults.set(payload, forKey: recoveryBackupKey)
            defaults.set(
                defaults.integer(forKey: encryptionVersionKey),
                forKey: recoveryBackupEncryptionVersionKey
            )
        }

        removeStoredPayload()
        defaults.set(Self.currentEncryptionVersion, forKey: encryptionVersionKey)
        defaults.removeObject(forKey: keychainRepairRequiredKey)
        defaults.removeObject(forKey: keychainAccessVersionKey)
        return true
    }

    private func recordKeychainAccessSuccess() {
        defaults.set(
            Self.currentKeychainAccessVersion,
            forKey: keychainAccessVersionKey
        )
        defaults.removeObject(forKey: keychainRepairRequiredKey)
    }

    static func live() -> EncryptedHistoryStore {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("EchoCopy", isDirectory: true)
            .appendingPathComponent("clipboard-history-v1.enc", isDirectory: false)

        return EncryptedHistoryStore(
            defaults: .standard,
            storageKey: "clipboardHistory",
            encryptionVersionKey: "clipboardHistoryEncryptionVersion",
            payloadFileURL: applicationSupportURL,
            keyProvider: KeychainHistoryKeyProvider()
        )
    }

    func save(_ items: [ClipboardItem], maximumPlaintextBytes: Int) throws {
        try save(
            items,
            maximumPlaintextBytes: maximumPlaintextBytes,
            keychainInteraction: .nonInteractive
        )
    }

    private func save(
        _ items: [ClipboardItem],
        maximumPlaintextBytes: Int,
        keychainInteraction: KeychainInteraction
    ) throws {
        let plaintext: Data
        do {
            plaintext = try JSONEncoder().encode(items)
        } catch {
            throw EncryptedHistoryStoreError.encodingFailed
        }

        guard plaintext.count <= maximumPlaintextBytes else {
            throw EncryptedHistoryStoreError.oversizedPayload
        }

        let keyData = try keyProvider.loadKeyData(interaction: keychainInteraction)
            ?? keyProvider.createKeyData()
        let key = try symmetricKey(from: keyData)
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(plaintext, using: key)
        } catch {
            throw EncryptedHistoryStoreError.encodingFailed
        }

        guard let combined = sealedBox.combined else {
            throw EncryptedHistoryStoreError.encodingFailed
        }

        var payload = Self.envelopeMagic
        payload.append(combined)
        guard payload.count <= maximumPlaintextBytes + Self.maximumEnvelopeOverhead else {
            throw EncryptedHistoryStoreError.oversizedPayload
        }

        try writeStoredPayload(payload)
        defaults.set(Self.currentEncryptionVersion, forKey: encryptionVersionKey)
        recordKeychainAccessSuccess()
    }

    func load(
        maximumPlaintextBytes: Int,
        allowKeychainInteraction: Bool = false
    ) throws -> [ClipboardItem]? {
        guard let payload = try readStoredPayload() else {
            return nil
        }

        if payload.starts(with: Self.envelopeMagic) {
            guard payload.count <= maximumPlaintextBytes + Self.maximumEnvelopeOverhead else {
                // Preserve encrypted data when it cannot be opened. The caller
                // blocks future writes so a recoverable history is not destroyed.
                throw EncryptedHistoryStoreError.oversizedPayload
            }
            let items = try decrypt(
                payload,
                maximumPlaintextBytes: maximumPlaintextBytes,
                keychainInteraction: allowKeychainInteraction
                    ? .userInitiated
                    : .nonInteractive
            )
            recordKeychainAccessSuccess()
            return items
        }

        guard payload.count <= maximumPlaintextBytes else {
            discardStoredPayloadAndRequireEncryption()
            throw EncryptedHistoryStoreError.oversizedPayload
        }

        guard defaults.integer(forKey: encryptionVersionKey) < Self.currentEncryptionVersion else {
            discardStoredPayloadAndRequireEncryption()
            throw EncryptedHistoryStoreError.plaintextDowngrade
        }

        let legacyItems: [ClipboardItem]
        do {
            legacyItems = try JSONDecoder().decode([ClipboardItem].self, from: payload)
        } catch {
            discardStoredPayloadAndRequireEncryption()
            throw EncryptedHistoryStoreError.decodingFailed
        }

        do {
            try save(
                legacyItems,
                maximumPlaintextBytes: maximumPlaintextBytes,
                keychainInteraction: allowKeychainInteraction
                    ? .userInitiated
                    : .nonInteractive
            )
        } catch {
            // A failed migration must never leave the old plaintext value behind.
            discardStoredPayloadAndRequireEncryption()
            throw error
        }

        return legacyItems
    }

    private func decrypt(
        _ payload: Data,
        maximumPlaintextBytes: Int,
        keychainInteraction: KeychainInteraction
    ) throws -> [ClipboardItem] {
        guard let keyData = try keyProvider.loadKeyData(interaction: keychainInteraction) else {
            throw EncryptedHistoryStoreError.missingKey
        }
        let key = try symmetricKey(from: keyData)
        let combined = Data(payload.dropFirst(Self.envelopeMagic.count))

        let plaintext: Data
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw EncryptedHistoryStoreError.authenticationFailed
        }

        guard plaintext.count <= maximumPlaintextBytes else {
            throw EncryptedHistoryStoreError.oversizedPayload
        }

        do {
            let items = try JSONDecoder().decode([ClipboardItem].self, from: plaintext)
            defaults.set(Self.currentEncryptionVersion, forKey: encryptionVersionKey)
            return items
        } catch {
            throw EncryptedHistoryStoreError.decodingFailed
        }
    }

    private func symmetricKey(from keyData: Data) throws -> SymmetricKey {
        guard keyData.count == 32 else {
            throw EncryptedHistoryStoreError.invalidKeyMaterial
        }
        return SymmetricKey(data: keyData)
    }

    private func discardStoredPayloadAndRequireEncryption() {
        removeStoredPayload()
        defaults.set(Self.currentEncryptionVersion, forKey: encryptionVersionKey)
    }

    private var hasStoredPayload: Bool {
        if let payloadFileURL,
           FileManager.default.fileExists(atPath: payloadFileURL.path) {
            return true
        }
        return defaults.data(forKey: storageKey) != nil
    }

    /// The live app keeps the potentially large encrypted blob out of
    /// UserDefaults so CFPreferences does not retain a second in-memory copy.
    /// Test stores and legacy callers can continue using UserDefaults by
    /// omitting `payloadFileURL`.
    private func readStoredPayload() throws -> Data? {
        guard let payloadFileURL else {
            return defaults.data(forKey: storageKey)
        }

        if FileManager.default.fileExists(atPath: payloadFileURL.path) {
            return try Data(contentsOf: payloadFileURL, options: .mappedIfSafe)
        }

        guard let legacyPayload = defaults.data(forKey: storageKey) else {
            return nil
        }

        // Migrate the already-encrypted payload atomically. Remove the old
        // preferences value only after the file is safely in place.
        try writePayloadFile(legacyPayload, to: payloadFileURL)
        defaults.removeObject(forKey: storageKey)
        return legacyPayload
    }

    private func writeStoredPayload(_ payload: Data) throws {
        guard let payloadFileURL else {
            defaults.set(payload, forKey: storageKey)
            return
        }

        try writePayloadFile(payload, to: payloadFileURL)
        defaults.removeObject(forKey: storageKey)
    }

    private func writePayloadFile(_ payload: Data, to fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try payload.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func removeStoredPayload() {
        if let payloadFileURL,
           FileManager.default.fileExists(atPath: payloadFileURL.path) {
            try? FileManager.default.removeItem(at: payloadFileURL)
        }
        defaults.removeObject(forKey: storageKey)
    }
}
