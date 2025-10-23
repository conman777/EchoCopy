import AppKit

/// Custom NSWindow class that intercepts miniaturization and hides instead
class MenuBarWindow: NSWindow {
    override func miniaturize(_ sender: Any?) {
        // Don't miniaturize - hide to menu bar instead
        self.orderOut(nil)
    }

    override func performMiniaturize(_ sender: Any?) {
        // Intercept miniaturize action
        self.orderOut(nil)
    }
}
