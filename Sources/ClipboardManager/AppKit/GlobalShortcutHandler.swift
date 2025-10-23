import AppKit
import ApplicationServices

/// Handles global keyboard shortcuts for the app
class GlobalShortcutHandler {
    private var eventMonitor: Any?
    weak var history: ClipboardHistory?
    weak var appDelegate: AppDelegate?

    init(history: ClipboardHistory, appDelegate: AppDelegate) {
        self.history = history
        self.appDelegate = appDelegate
        setupGlobalShortcuts()
    }

    // MARK: - Private: Setup

    private func setupGlobalShortcuts() {
        // Check if we have accessibility permissions
        let trusted = AXIsProcessTrusted()

        if !trusted {
            // Request permissions by showing system dialog
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
    }

    // MARK: - Private: Event Handling

    private func handleGlobalKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let optionPressed = modifiers == .option
        let cmdAltPressed = modifiers.contains([.command, .option])

        // Check for Option+V to show popup
        if optionPressed, event.charactersIgnoringModifiers == "v" {
            appDelegate?.showPopupWindow()
            return
        }

        // Only handle if Cmd+Option is pressed for quick paste
        guard cmdAltPressed else { return }

        // Numbers 1-9 for quick paste
        if let character = event.charactersIgnoringModifiers?.first,
           let digit = Int(String(character)), digit >= 1, digit <= 9 {
            pasteQuickItem(at: digit - 1)
        }
    }

    private func pasteQuickItem(at index: Int) {
        guard let history = history else { return }
        guard index >= 0 && index < history.items.count else { return }

        let item = history.items[index]

        NSPasteboard.general.clearContents()
        switch item.contentType {
        case .text, .url:
            NSPasteboard.general.setString(item.content, forType: .string)
        case .image:
            if let data = Data(base64Encoded: item.content),
               let image = NSImage(data: data) {
                NSPasteboard.general.writeObjects([image])
            }
        case .file:
            NSPasteboard.general.setString(item.content, forType: .string)
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
