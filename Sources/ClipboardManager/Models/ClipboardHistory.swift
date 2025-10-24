import Foundation
import Combine

/// Manages clipboard history with persistent storage
class ClipboardHistory: ObservableObject {
    @Published var items: [ClipboardItem] = []

    init() {
        loadHistory()
    }

    /// Add a new item to the history (or ignore if it's invalid/duplicate)
    /// - Parameters:
    ///   - content: The clipboard content (must not be empty after trimming)
    ///   - contentType: Type of content (default: .text)
    ///   - filename: Optional filename for files/images
    ///   - rtfContent: Optional RTF formatting data
    func addItem(
        _ content: String,
        contentType: ContentType = .text,
        filename: String? = nil,
        rtfContent: String? = nil
    ) {
        // Validate content is not empty
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        // Skip duplicate content (prevent consecutive identical items)
        if let lastItem = items.first, lastItem.content == content {
            return
        }

        let newItem = ClipboardItem(
            content: content,
            contentType: contentType,
            filename: filename,
            rtfContent: rtfContent
        )
        items.insert(newItem, at: 0)

        // Trim to max items
        if items.count > Constants.maxHistoryItems {
            items = Array(items.prefix(Constants.maxHistoryItems))
        }

        saveHistory()
    }

    /// Remove item at specified index
    /// - Parameter index: Index of item to remove
    func removeItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
        saveHistory()
    }

    /// Toggle pin status for an item, preserving all other fields
    /// - Parameter item: The item to toggle
    func togglePin(for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        // BUG FIX: Use updating() method to preserve all fields
        let toggled = items[index].updating(isPinned: !items[index].isPinned)
        items[index] = toggled
        saveHistory()
    }

    /// Clear all unpinned items from history
    func clearHistory() {
        items = items.filter { $0.isPinned }
        saveHistory()
    }

    // MARK: - Private: Persistence

    private func saveHistory() {
        do {
            let encoded = try JSONEncoder().encode(items)
            UserDefaults.standard.set(encoded, forKey: Constants.clipboardHistoryStorageKey)
        } catch {
            print("❌ Error saving clipboard history: \(error.localizedDescription)")
        }
    }

    private func loadHistory() {
        do {
            guard let data = UserDefaults.standard.data(forKey: Constants.clipboardHistoryStorageKey) else {
                // No saved history - this is normal on first run
                return
            }

            let decoded = try JSONDecoder().decode([ClipboardItem].self, from: data)
            items = decoded
        } catch {
            print("⚠️ Error loading clipboard history: \(error.localizedDescription)")
            // On error, start with empty history rather than crashing
            items = []
        }
    }
}
