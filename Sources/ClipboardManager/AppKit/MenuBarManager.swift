import AppKit
import Combine

/// Manages the menu bar status item and quick access menu
class MenuBarManager {
    private var statusItem: NSStatusItem?
    private weak var history: ClipboardHistory?
    private weak var appDelegate: AppDelegate?
    private var historySubscription: AnyCancellable?

    init(history: ClipboardHistory, appDelegate: AppDelegate) {
        self.history = history
        self.appDelegate = appDelegate
        setupMenuBar()
        setupHistoryObserver()
    }

    // MARK: - Private: Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: Constants.Accessibility.clipboardManagerDescription)
            button.target = self
            button.action = #selector(toggleWindow)
        }

        updateMenu()
    }

    private func setupHistoryObserver() {
        // Subscribe to changes in the history
        historySubscription = history?.objectWillChange.sink { [weak self] in
            self?.updateMenu()
        }
    }

    // MARK: - Private: Menu Updates

    private func updateMenu() {
        DispatchQueue.main.async { [weak self] in
            let menu = NSMenu()

            guard let history = self?.history else { return }
            guard let strongSelf = self else { return }

            // Show top 10 items
            let topItems = Array(history.items.prefix(10))
            for (index, item) in topItems.enumerated() {
                let preview = String(item.content.prefix(40))
                let title = "\(index + 1). \(preview)..."
                let menuItem = NSMenuItem(title: title, action: #selector(MenuBarManager.pasteItem(_:)), keyEquivalent: "")
                menuItem.representedObject = item
                menuItem.target = strongSelf
                menu.addItem(menuItem)
            }

            if !topItems.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }

            let openItem = NSMenuItem(title: "Open ClipboardManager", action: #selector(MenuBarManager.openWindow), keyEquivalent: "")
            openItem.target = strongSelf
            menu.addItem(openItem)

            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

            self?.statusItem?.menu = menu
        }
    }

    // MARK: - Private: Menu Actions

    @objc private func toggleWindow() {
        appDelegate?.toggleMainWindow()
    }

    @objc private func openWindow() {
        appDelegate?.showMainWindow()
    }

    @objc private func pasteItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? ClipboardItem {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.content, forType: .string)
        }
    }
}
