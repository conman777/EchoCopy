import SwiftUI

/// Main app entry point for ClipboardManager
@main
struct ClipboardManagerApp: App {
    @StateObject private var history: ClipboardHistory
    private let clipboardMonitor: ClipboardMonitor
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(history)
                .onAppear {
                    // Configure window when content appears
                    if let window = NSApp.windows.first(where: { !$0.isKind(of: NSPanel.self) }) {
                        appDelegate.applyWindowBehavior(to: window)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }

    init() {
        let historyInstance = ClipboardHistory()
        _history = StateObject(wrappedValue: historyInstance)

        clipboardMonitor = ClipboardMonitor(history: historyInstance)
        appDelegate.history = historyInstance
        clipboardMonitor.start()
    }
}
