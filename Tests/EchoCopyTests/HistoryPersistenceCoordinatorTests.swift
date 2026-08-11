import Foundation
import XCTest
@testable import EchoCopy

final class HistoryPersistenceCoordinatorTests: XCTestCase {
    func testScheduledSavesCoalesceToLatestSnapshot() throws {
        let context = makeContext()
        defer { context.cleanup() }

        let coordinator = HistoryPersistenceCoordinator(
            historyStore: context.store,
            debounceInterval: 0.05,
            queue: DispatchQueue(label: "EchoCopyTests.persistence.coalescing")
        )
        let supersededCompletion = expectation(description: "superseded save is not completed")
        supersededCompletion.isInverted = true
        let latestCompletion = expectation(description: "latest save completes")

        coordinator.scheduleSave(
            [ClipboardItem(content: "first", contentType: .text)],
            generation: 1
        ) { _, _ in
            supersededCompletion.fulfill()
        }

        coordinator.scheduleSave(
            [ClipboardItem(content: "latest", contentType: .text)],
            generation: 2
        ) { generation, result in
            XCTAssertEqual(generation, 2)
            do {
                let persistedItems = try result.get()
                XCTAssertEqual(persistedItems.map(\.content), ["latest"])
            } catch {
                XCTFail("Unexpected persistence error: \(error)")
            }
            latestCompletion.fulfill()
        }

        wait(for: [latestCompletion, supersededCompletion], timeout: 0.4)

        let loaded = try XCTUnwrap(
            context.store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        )
        XCTAssertEqual(loaded.map(\.content), ["latest"])
    }

    func testFlushCancelsDebounceAndPreservesPinnedItemsWithinLimit() throws {
        let context = makeContext()
        defer { context.cleanup() }

        let coordinator = HistoryPersistenceCoordinator(
            historyStore: context.store,
            maximumItems: 2,
            debounceInterval: 10,
            queue: DispatchQueue(label: "EchoCopyTests.persistence.flush")
        )
        let pinned = ClipboardItem(
            content: "pinned",
            contentType: .text,
            isPinned: true
        )
        let recent = ClipboardItem(content: "recent", contentType: .text)
        let oldest = ClipboardItem(content: "oldest", contentType: .text)

        coordinator.scheduleSave([oldest], generation: 1) { _, _ in
            XCTFail("The pending debounced save should have been cancelled by flush")
        }

        let flushedItems = try coordinator.flushSave([pinned, recent, oldest]).get()
        XCTAssertEqual(flushedItems.map(\.id), [pinned.id, recent.id])

        let loaded = try XCTUnwrap(
            context.store.load(maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        )
        XCTAssertEqual(loaded.map(\.id), [pinned.id, recent.id])
    }

    private func makeContext() -> CoordinatorStoreContext {
        let suiteName = "EchoCopyTests.HistoryPersistenceCoordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let storageKey = "history"
        let versionKey = "historyEncryptionVersion"
        let store = EncryptedHistoryStore(
            defaults: defaults,
            storageKey: storageKey,
            encryptionVersionKey: versionKey,
            keyProvider: CoordinatorHistoryKeyProvider()
        )

        return CoordinatorStoreContext(
            suiteName: suiteName,
            defaults: defaults,
            store: store
        )
    }
}

private final class CoordinatorHistoryKeyProvider: HistoryKeyProviding {
    private let lock = NSLock()
    private var keyData: Data?

    func loadKeyData() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return keyData
    }

    func createKeyData() throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        if let keyData {
            return keyData
        }

        let created = Data(repeating: 0x5A, count: 32)
        keyData = created
        return created
    }
}

private struct CoordinatorStoreContext {
    let suiteName: String
    let defaults: UserDefaults
    let store: EncryptedHistoryStore

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
