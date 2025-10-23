import AppKit

/// Application delegate for ClipboardManager
class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    var menuBarManager: MenuBarManager?
    var shortcutHandler: GlobalShortcutHandler?
    var popupWindowManager: PopupWindowManager?
    var windowDelegate: MenuBarWindowDelegate?
    var localEventMonitor: Any?
    weak var history: ClipboardHistory?
    private var hasAppliedPreferredSize = false

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hide dock icon as early as possible
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar and keyboard shortcuts
        if let history = history {
            menuBarManager = MenuBarManager(history: history, appDelegate: self)
            shortcutHandler = GlobalShortcutHandler(history: history, appDelegate: self)
            popupWindowManager = PopupWindowManager(history: history)
        }

        // Setup window delegate for all windows - do this after a small delay to ensure windows are ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupWindowBehavior()
        }
    }

    // MARK: - Public: Window Management

    /// Apply configured behavior to a window
    func applyWindowBehavior(to window: NSWindow) {
        configureWindow(window)
    }

    /// Toggle main window visibility
    @objc func toggleMainWindow() {
        if let window = mainWindow, window.isVisible {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    /// Show the main window
    @objc func showMainWindow() {
        // Find the main window from the app's windows
        if let window = NSApp.windows.first(where: { !$0.isKind(of: NSPanel.self) }) {
            configureWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.mainWindow = window
        }
    }

    /// Show the popup window for Option+V
    @objc func showPopupWindow() {
        popupWindowManager?.showPopup()
    }

    // MARK: - Private: Window Configuration

    private func setupWindowBehavior() {
        for window in NSApp.windows {
            configureWindow(window)
        }

        // Add local event monitor to intercept Cmd+M as a backup
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Check for Cmd+M
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers == .command && event.charactersIgnoringModifiers == "m" {
                    // Hide window to menu bar instead of minimizing
                    if let window = self?.mainWindow, window.isVisible {
                        window.orderOut(nil)
                        return nil  // Consume the event
                    }
                }
                return event  // Pass through other events
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        if windowDelegate == nil {
            windowDelegate = MenuBarWindowDelegate()
        }

        // Configure window to behave like an NSPanel (menu bar window)
        // This prevents minimize to dock behavior
        window.delegate = windowDelegate

        // Hide when app loses focus (key NSPanel behavior)
        window.hidesOnDeactivate = true

        // Make it a floating window
        window.level = .floating

        // Configure collection behavior for proper floating window behavior
        var collectionBehavior = window.collectionBehavior
        collectionBehavior.insert(.canJoinAllSpaces)
        collectionBehavior.insert(.fullScreenAuxiliary)
        collectionBehavior.insert(.transient)
        window.collectionBehavior = collectionBehavior

        // Hide the minimize and zoom buttons completely
        if let miniButton = window.standardWindowButton(.miniaturizeButton) {
            miniButton.isHidden = true
            // Intercept just in case the button remains visible due to style changes
            miniButton.target = self
            miniButton.action = #selector(handleMiniaturizeButton(_:))
        }
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Remove Dock minimization entirely
        window.styleMask.remove(.miniaturizable)

        // As a fallback, observe miniaturize attempts and immediately hide instead
        NotificationCenter.default.addObserver(
            forName: NSWindow.willMiniaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self] note in
            if let w = note.object as? NSWindow {
                w.orderOut(nil)
                self?.mainWindow = w
            }
        }

        // Store reference
        self.mainWindow = window

        window.minSize = NSSize(width: 320, height: 260)

        if !hasAppliedPreferredSize {
            let preferredContentSize = NSSize(width: 340, height: 360)
            window.setContentSize(preferredContentSize)
            hasAppliedPreferredSize = true
        }
    }

    @objc private func handleMiniaturizeButton(_ sender: Any?) {
        if let window = self.mainWindow {
            window.orderOut(nil)
        }
    }
}
