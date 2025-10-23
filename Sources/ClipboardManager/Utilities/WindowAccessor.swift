import SwiftUI
import AppKit

/// NSView that detects when it's been added to a window
final class _WindowDetectorView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = self.window {
            onResolve?(w)
            // Run once, then clear the closure
            onResolve = nil
        }
    }
}

/// SwiftUI representable for accessing the underlying NSWindow
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> _WindowDetectorView {
        let v = _WindowDetectorView(frame: .zero)
        v.onResolve = onResolve
        return v
    }

    func updateNSView(_ nsView: _WindowDetectorView, context: Context) {
        // No-op
    }
}
