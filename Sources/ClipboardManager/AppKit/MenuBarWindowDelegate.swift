import AppKit

/// Window delegate that handles menu bar behavior (hide instead of close/minimize)
class MenuBarWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of close
        sender.orderOut(nil)
        return false
    }

    func windowShouldMiniaturize(_ sender: NSWindow) -> Bool {
        // Prevent minimize to dock, hide to menu bar instead
        sender.orderOut(nil)
        return false  // Don't allow the miniaturize
    }

    func window(
        _ window: NSWindow,
        willUseFullScreenPresentationOptions options: NSApplication.PresentationOptions = []
    ) -> NSApplication.PresentationOptions {
        return options
    }
}
