import Foundation

/// Records the final pasteboard change count produced by EchoCopy itself so
/// the polling monitor does not immediately re-import that write as a new item.
final class PasteboardWriteTracker: @unchecked Sendable {
    static let shared = PasteboardWriteTracker()

    private let lock = NSLock()
    private var internalChangeCount: Int?

    func recordInternalWrite(changeCount: Int) {
        lock.lock()
        internalChangeCount = changeCount
        lock.unlock()
    }

    func consumeIfInternal(changeCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let internalChangeCount else { return false }
        self.internalChangeCount = nil
        return internalChangeCount == changeCount
    }
}
