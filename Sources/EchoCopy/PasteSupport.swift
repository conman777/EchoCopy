import AppKit
import Carbon.HIToolbox
import Foundation

enum MenuBarHistoryPresentation {
    static let maximumVisibleRows = 10

    static func orderedItems(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }

    static func visibleRowCount(for itemCount: Int) -> Int {
        min(max(itemCount, 0), maximumVisibleRows)
    }
}

enum PasteKeyboardEventFactory {
    static func makeCommandVEvents() -> (keyDown: CGEvent, keyUp: CGEvent)? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: false
              ) else {
            return nil
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        return (keyDown, keyUp)
    }
}

@MainActor
enum PasteExecutor {
    static func pastePreparedClipboard(
        into targetApplication: NSRunningApplication?
    ) {
        if let targetApplication,
           !targetApplication.isTerminated,
           !targetApplication.isActive {
            targetApplication.activate(options: [.activateIgnoringOtherApps])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard let events = PasteKeyboardEventFactory.makeCommandVEvents() else {
                return
            }
            events.keyDown.post(tap: .cghidEventTap)
            events.keyUp.post(tap: .cghidEventTap)
        }
    }
}
