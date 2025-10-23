import AppKit
import SwiftUI

/// Manages the Option+V popup window
class PopupWindowManager {
    private var popupWindow: NSWindow?
    private weak var history: ClipboardHistory?
    private var clickOutsideMonitor: Any?

    init(history: ClipboardHistory) {
        self.history = history
    }

    /// Show the clipboard popup window near the cursor
    func showPopup() {
        guard let history = history else { return }

        // Close existing popup if open
        popupWindow?.close()

        // Create hosting controller with popup view
        let popupView = PopupView(history: history, onDismiss: { [weak self] in
            self?.popupWindow?.close()
            self?.popupWindow = nil
        })
        .environmentObject(history)

        let hostingController = NSHostingController(rootView: popupView)
        hostingController.view.frame = NSRect(
            x: 0,
            y: 0,
            width: Constants.PopupWindow.width,
            height: Constants.PopupWindow.height
        )

        // Position near mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let frame = NSRect(
            x: mouseLocation.x - 120,
            y: mouseLocation.y - 200,
            width: Constants.PopupWindow.width,
            height: Constants.PopupWindow.height
        )

        // Create panel (better for popups than regular window)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false  // We're adding custom shadows in SwiftUI
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // Show panel
        panel.orderFrontRegardless()
        panel.makeKey()

        self.popupWindow = panel

        // Monitor clicks outside the popup
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let popupWindow = self.popupWindow else { return }

            // Get mouse location in screen coordinates
            let clickLocation = NSEvent.mouseLocation
            let windowFrame = popupWindow.frame

            // Check if click is outside popup window
            if !windowFrame.contains(clickLocation) {
                self.closePopup()
            }
        }
    }

    /// Close the popup window and cleanup
    func closePopup() {
        // Remove click monitor
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }

        popupWindow?.close()
        popupWindow = nil
    }

    deinit {
        closePopup()
    }
}
