import AppKit
import Foundation
import Security
import XCTest

@testable import EchoCopy

@MainActor
final class ClipboardRecoveryTests: XCTestCase {
    func testMissingKeyAtStartupPreservesHistoryOnQuit() throws {
        let suite = "EchoCopyTests.Recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = RecoveryTestKeyProvider()
        let store = EncryptedHistoryStore(
            defaults: defaults, storageKey: "history", encryptionVersionKey: "version",
            keyProvider: provider)
        try store.save(
            [ClipboardItem(content: "saved history")],
            maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        let original = defaults.data(forKey: "history")
        provider.key = nil
        let history = ClipboardHistory(historyStore: store)
        XCTAssertNotNil(history.persistenceError)
        history.flushPersistence()
        XCTAssertEqual(
            defaults.data(forKey: "history"), original,
            "Quitting after a failed history read must preserve the encrypted payload")
    }

    func testUnlockPreservesItemsCopiedWhileLocked() throws {
        let suite = "EchoCopyTests.Recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = RecoveryTestKeyProvider()
        let store = EncryptedHistoryStore(
            defaults: defaults, storageKey: "history", encryptionVersionKey: "version",
            keyProvider: provider)
        try store.save(
            [ClipboardItem(content: "saved history")],
            maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        provider.locked = true
        let history = ClipboardHistory(historyStore: store)
        history.addItem("copied while locked")
        XCTAssertEqual(history.items.map(\.content), ["copied while locked"])
        let sessionID = try XCTUnwrap(history.items.first?.id)
        history.togglePin(for: try XCTUnwrap(history.items.first))
        history.retryHistoryUnlock()
        XCTAssertTrue(history.isPersistenceBlocked)
        XCTAssertEqual(history.items.first?.id, sessionID)
        provider.locked = false
        history.retryHistoryUnlock()
        XCTAssertTrue(
            history.items.contains { $0.content == "copied while locked" },
            "Repair must retain new session history")
        XCTAssertEqual(history.items.map(\.content), ["copied while locked", "saved history"])
        XCTAssertTrue(history.items[0].isPinned)
        history.flushPersistence()
        let restarted = ClipboardHistory(historyStore: store)
        XCTAssertEqual(restarted.items.map(\.id), history.items.map(\.id))
    }

    func testRestoredFinderFileRemainsAFilePasteboardObject() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("EchoCopyTests.Recovery.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let url = URL(fileURLWithPath: "/private/tmp/echocopy-review-example.txt")
        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))
        let urls = try XCTUnwrap(pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL])
        let first = try XCTUnwrap(urls.first)
        // Older versions classified Finder file URLs as ordinary links.
        let item = ClipboardItem(content: first.absoluteString!, contentType: .url)
        XCTAssertTrue(
            PasteboardWriter.write(item, to: pasteboard, writeTracker: PasteboardWriteTracker()))
        XCTAssertTrue(
            pasteboard.canReadObject(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
            "Restoring a copied file must preserve file URL semantics")
    }

    func testCorruptHistoryIsPreservedAfterCopyAndQuit() throws {
        let suite = "EchoCopyTests.Recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = EncryptedHistoryStore(
            defaults: defaults, storageKey: "history", encryptionVersionKey: "version",
            keyProvider: RecoveryTestKeyProvider())
        try store.save(
            [ClipboardItem(content: "saved history")],
            maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        var corrupted = try XCTUnwrap(defaults.data(forKey: "history"))
        corrupted[corrupted.count - 1] ^= 1
        defaults.set(corrupted, forKey: "history")
        let history = ClipboardHistory(historyStore: store)
        let originalError = history.persistenceError
        XCTAssertTrue(history.isPersistenceBlocked)
        history.addItem("new copy")
        history.flushPersistence()
        XCTAssertEqual(defaults.data(forKey: "history"), corrupted)
        XCTAssertEqual(history.persistenceError, originalError)
        XCTAssertFalse(history.canRetryHistoryUnlock)
    }

    func testRepairAfterFailedSaveDoesNotRestoreDeletedItems() throws {
        let suite = "EchoCopyTests.Recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = RecoveryTestKeyProvider()
        let store = EncryptedHistoryStore(
            defaults: defaults, storageKey: "history", encryptionVersionKey: "version",
            keyProvider: provider)
        try store.save(
            [ClipboardItem(content: "delete me")],
            maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        let history = ClipboardHistory(historyStore: store)
        provider.locked = true
        history.clearHistory()
        history.flushPersistence()
        XCTAssertTrue(history.canRetryHistoryUnlock)
        provider.locked = false
        history.retryHistoryUnlock()
        history.flushPersistence()
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertEqual(
            try store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)?.count, 0)
    }

    func testFileEntriesRestoreBothURLsAndLegacyPaths() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("EchoCopyTests.Recovery.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let url = URL(fileURLWithPath: "/private/tmp/EchoCopy example.txt")
        for content in [url.absoluteString, url.path] {
            let tracker = PasteboardWriteTracker()
            XCTAssertTrue(
                PasteboardWriter.write(
                    ClipboardItem(content: content, contentType: .file), to: pasteboard,
                    writeTracker: tracker))
            let restored =
                pasteboard.readObjects(
                    forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            XCTAssertEqual(restored, [url])
            XCTAssertTrue(tracker.consumeIfInternal(changeCount: pasteboard.changeCount))
        }
    }

}

private final class RecoveryTestKeyProvider: HistoryKeyProviding {
    var key: Data? = Data(repeating: 0x4A, count: 32)
    var locked = false
    func loadKeyData() throws -> Data? {
        if locked { throw EncryptedHistoryStoreError.keychain(errSecInteractionNotAllowed) }
        return key
    }
    func createKeyData() throws -> Data {
        let fresh = Data(repeating: 0x7B, count: 32)
        key = fresh
        return fresh
    }
}
