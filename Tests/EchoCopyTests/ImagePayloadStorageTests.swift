import CryptoKit
import Foundation
import XCTest
@testable import EchoCopy

@MainActor
final class ImagePayloadStorageTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var payloadDirectoryURL: URL!
    private var store: EncryptedHistoryStore!

    override func setUp() async throws {
        suiteName = "EchoCopyTests.ImagePayloads.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        payloadDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoCopyTests.Payloads.\(UUID().uuidString)", isDirectory: true)
        store = EncryptedHistoryStore(
            defaults: defaults,
            storageKey: "history",
            encryptionVersionKey: "historyEncryptionVersion",
            itemPayloadDirectoryURL: payloadDirectoryURL,
            keyProvider: FixedKeyProvider()
        )
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: payloadDirectoryURL)
    }

    func testImageBytesStayOutOfTheHistoryIndexAndRoundTrip() throws {
        let imageBytes = Data((0..<4096).map { UInt8($0 % 251) })
        let history = ClipboardHistory(historyStore: store)

        let item = try XCTUnwrap(history.makeImageItem(imageBytes, filename: "shot.png"))
        XCTAssertTrue(item.hasExternalPayload)
        XCTAssertEqual(item.content, "")
        XCTAssertEqual(item.payloadByteCount, imageBytes.count)

        history.addPreparedItem(item)
        history.flushPersistence()

        let index = try XCTUnwrap(defaults.data(forKey: "history"))
        XCTAssertLessThan(index.count, imageBytes.count)

        let payloadFile = try XCTUnwrap(payloadFiles().first)
        XCTAssertNil(try Data(contentsOf: payloadFile).range(of: imageBytes.prefix(64)))

        let restarted = ClipboardHistory(historyStore: store)
        let restored = try XCTUnwrap(restarted.items.first)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertEqual(restarted.imageData(for: restored), imageBytes)
    }

    func testLegacyInlineImagesMoveToPayloadFilesOnLoad() throws {
        let imageBytes = Data((0..<8192).map { UInt8($0 % 13) })
        let legacyItem = ClipboardItem(
            content: imageBytes.base64EncodedString(),
            contentType: .image,
            isPinned: true,
            filename: "legacy.png"
        )
        try store.save([legacyItem], maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)

        let history = ClipboardHistory(historyStore: store)
        let migrated = try XCTUnwrap(history.items.first)
        XCTAssertEqual(migrated.id, legacyItem.id)
        XCTAssertTrue(migrated.isPinned)
        XCTAssertTrue(migrated.hasExternalPayload)
        XCTAssertEqual(migrated.content, "")
        XCTAssertEqual(history.imageData(for: migrated), imageBytes)

        history.flushPersistence()
        let reloaded = try XCTUnwrap(
            store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)?.first
        )
        XCTAssertEqual(reloaded.content, "")
        XCTAssertEqual(reloaded.payloadDigest, migrated.payloadDigest)
    }

    func testUnreferencedPayloadsArePrunedAfterGracePeriod() throws {
        let keptID = UUID()
        let removedID = UUID()
        try store.saveItemPayload(Data("kept".utf8), for: keptID)
        try store.saveItemPayload(Data("removed".utf8), for: removedID)

        store.removeUnreferencedItemPayloads(keeping: [keptID])
        XCTAssertEqual(payloadFiles().count, 2, "fresh payloads survive the grace period")

        store.removeUnreferencedItemPayloads(
            keeping: [keptID],
            now: Date().addingTimeInterval(120)
        )
        XCTAssertEqual(
            payloadFiles().map { $0.deletingPathExtension().lastPathComponent },
            [keptID.uuidString]
        )
    }

    func testPayloadFromAnotherItemIsRejected() throws {
        let history = ClipboardHistory(historyStore: store)
        let first = try XCTUnwrap(history.makeImageItem(Data("first".utf8), filename: nil))
        let second = try XCTUnwrap(history.makeImageItem(Data("second".utf8), filename: nil))

        let firstURL = payloadDirectoryURL.appendingPathComponent("\(first.id.uuidString).enc")
        let secondURL = payloadDirectoryURL.appendingPathComponent("\(second.id.uuidString).enc")
        try FileManager.default.removeItem(at: firstURL)
        try FileManager.default.copyItem(at: secondURL, to: firstURL)

        XCTAssertNil(history.imageData(for: first))
        XCTAssertEqual(history.imageData(for: second), Data("second".utf8))
    }

    private func payloadFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: payloadDirectoryURL,
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.pathExtension == "enc" }
    }
}

private final class FixedKeyProvider: HistoryKeyProviding {
    private let keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }

    func loadKeyData() throws -> Data? { keyData }
    func createKeyData() throws -> Data { keyData }
}
