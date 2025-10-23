import AppKit
import Foundation

/// Monitors the system clipboard for changes and updates history
class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let history: ClipboardHistory

    init(history: ClipboardHistory) {
        self.history = history
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Start monitoring the clipboard
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Constants.clipboardCheckInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    /// Stop monitoring the clipboard
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private: Clipboard Monitoring

    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount

        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        let pasteboard = NSPasteboard.general

        // Check for URL (highest priority)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL], let url = urls.first {
            history.addItem(url.absoluteString ?? "", contentType: .url)
            return
        }

        // Check for image
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], let nsImage = images.first {
            if let tiffData = nsImage.tiffRepresentation {
                let base64 = tiffData.base64EncodedString().split(separator: "\n").joined()
                history.addItem(base64, contentType: .image, filename: "image.png")
            }
            return
        }

        // Check for text with RTF support
        if let stringContent = pasteboard.string(forType: .string) {
            let trimmed = stringContent.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            var rtfBase64: String? = nil

            // Try to capture RTF formatting if available
            if let rtfData = pasteboard.data(forType: .rtf) {
                rtfBase64 = rtfData.base64EncodedString().split(separator: "\n").joined()
            }

            history.addItem(stringContent, contentType: .text, rtfContent: rtfBase64)
        }
    }

    deinit {
        stop()
    }
}
