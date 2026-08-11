import Foundation

/// Serializes, coalesces, and performs expensive history persistence away from
/// the main thread. The caller still owns the in-memory history on MainActor.
final class HistoryPersistenceCoordinator {
    typealias Completion = (Int, Result<[ClipboardItem], Error>) -> Void

    private struct PendingSave {
        let items: [ClipboardItem]
        let generation: Int
        let completion: Completion
    }

    private struct SizedItem {
        let item: ClipboardItem
        let encodedByteCount: Int
    }

    private let historyStore: EncryptedHistoryStore
    private let maximumItems: Int
    private let maximumPlaintextBytes: Int
    private let debounceInterval: TimeInterval
    private let queue: DispatchQueue

    // Accessed only from `queue`.
    private var pendingSave: PendingSave?
    private var pendingToken: UInt64 = 0

    init(
        historyStore: EncryptedHistoryStore,
        maximumItems: Int = 500,
        maximumPlaintextBytes: Int = ClipboardPolicy.maxHistoryBytes,
        debounceInterval: TimeInterval = 0.25,
        queue: DispatchQueue = DispatchQueue(
            label: "com.yourcompany.echocopy.history-persistence",
            qos: .utility
        )
    ) {
        self.historyStore = historyStore
        self.maximumItems = maximumItems
        self.maximumPlaintextBytes = maximumPlaintextBytes
        self.debounceInterval = debounceInterval
        self.queue = queue
    }

    func scheduleSave(
        _ items: [ClipboardItem],
        generation: Int,
        completion: @escaping Completion
    ) {
        let pending = PendingSave(
            items: items,
            generation: generation,
            completion: completion
        )

        queue.async { [weak self] in
            guard let self else { return }

            self.pendingToken &+= 1
            let token = self.pendingToken
            self.pendingSave = pending

            self.queue.asyncAfter(deadline: .now() + self.debounceInterval) { [weak self] in
                guard let self,
                      self.pendingToken == token,
                      let pendingSave = self.pendingSave else {
                    return
                }

                self.pendingSave = nil
                let result = self.persist(pendingSave.items)

                DispatchQueue.main.async {
                    pendingSave.completion(pendingSave.generation, result)
                }
            }
        }
    }

    /// Persists immediately after all previously-started work completes. This
    /// is used during orderly app termination so the debounce window cannot
    /// lose the most recent clipboard item.
    func flushSave(_ items: [ClipboardItem]) -> Result<[ClipboardItem], Error> {
        queue.sync {
            pendingToken &+= 1
            pendingSave = nil
            return persist(items)
        }
    }

    private func persist(_ items: [ClipboardItem]) -> Result<[ClipboardItem], Error> {
        Result {
            let boundedItems = try itemsWithinStorageBudget(items)
            try historyStore.save(
                boundedItems,
                maximumPlaintextBytes: maximumPlaintextBytes
            )
            return boundedItems
        }
    }

    private func itemsWithinStorageBudget(_ items: [ClipboardItem]) throws -> [ClipboardItem] {
        let encoder = JSONEncoder()
        var sizedItems = try items.map {
            SizedItem(item: $0, encodedByteCount: try encoder.encode($0).count)
        }

        var estimatedArrayByteCount = 2 // Opening and closing brackets.
        estimatedArrayByteCount += sizedItems.reduce(0) { $0 + $1.encodedByteCount }
        estimatedArrayByteCount += max(0, sizedItems.count - 1) // Commas.

        while sizedItems.count > maximumItems || estimatedArrayByteCount > maximumPlaintextBytes {
            guard !sizedItems.isEmpty else {
                throw EncryptedHistoryStoreError.oversizedPayload
            }

            let removalIndex = sizedItems.lastIndex(where: { !$0.item.isPinned })
                ?? sizedItems.count - 1
            let removed = sizedItems.remove(at: removalIndex)
            estimatedArrayByteCount -= removed.encodedByteCount
            if !sizedItems.isEmpty {
                estimatedArrayByteCount -= 1
            }
        }

        var boundedItems = sizedItems.map(\.item)

        // Verify the estimate against JSONEncoder itself. This normally encodes
        // once; the loop is a defensive fallback if array encoding adds more
        // bytes than the per-item estimate on a future OS.
        while try encoder.encode(boundedItems).count > maximumPlaintextBytes {
            guard !boundedItems.isEmpty else {
                throw EncryptedHistoryStoreError.oversizedPayload
            }

            let removalIndex = boundedItems.lastIndex(where: { !$0.isPinned })
                ?? boundedItems.count - 1
            boundedItems.remove(at: removalIndex)
        }

        return boundedItems
    }
}
