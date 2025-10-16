import SwiftUI
import AppKit
import Foundation
import Combine

// MARK: - Data Models

enum ContentType: String, Codable {
    case text
    case image
    case file
    case url
}

struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    let content: String  // Plain text or base64 for images
    let contentType: ContentType
    let timestamp: Date
    let isPinned: Bool
    let filename: String?  // For file/image references
    let rtfContent: String?  // Rich Text Format (base64 encoded)

    init(content: String, contentType: ContentType = .text, isPinned: Bool = false, filename: String? = nil, rtfContent: String? = nil) {
        self.id = UUID()
        self.content = content
        self.contentType = contentType
        self.timestamp = Date()
        self.isPinned = isPinned
        self.filename = filename
        self.rtfContent = rtfContent
    }
}

class ClipboardHistory: ObservableObject {
    @Published var items: [ClipboardItem] = []
    private let maxItems = 500
    private let storageKey = "clipboardHistory"

    init() {
        loadHistory()
    }

    func addItem(_ content: String, contentType: ContentType = .text, filename: String? = nil, rtfContent: String? = nil) {
        if let lastItem = items.first, lastItem.content == content {
            return
        }

        let newItem = ClipboardItem(content: content, contentType: contentType, filename: filename, rtfContent: rtfContent)
        items.insert(newItem, at: 0)

        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }

        saveHistory()
    }

    func removeItem(at index: Int) {
        items.remove(at: index)
        saveHistory()
    }

    func togglePin(for item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let toggled = ClipboardItem(content: items[index].content, isPinned: !items[index].isPinned)
            items[index] = toggled
            saveHistory()
        }
    }

    func clearHistory() {
        items.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded
        }
    }
}

// MARK: - Clipboard Monitoring

class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let history: ClipboardHistory
    private let checkInterval: TimeInterval = 0.5

    init(history: ClipboardHistory) {
        self.history = history
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount

        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount

            let pasteboard = NSPasteboard.general

            // Check for URL
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL], let url = urls.first {
                history.addItem(url.absoluteString ?? "", contentType: .url)
                return
            }

            // Check for image
            if let image = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], let nsImage = image.first {
                if let tiffData = nsImage.tiffRepresentation {
                    let base64 = tiffData.base64EncodedString().split(separator: Character("\n")).joined()
                    history.addItem(base64, contentType: .image, filename: "image.png")
                }
                return
            }

            // Check for text with RTF support
            if let stringContent = pasteboard.string(forType: .string) {
                if !stringContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    var rtfBase64: String? = nil

                    // Try to capture RTF formatting
                    if let rtfData = pasteboard.data(forType: .rtf) {
                        rtfBase64 = rtfData.base64EncodedString().split(separator: Character("\n")).joined()
                    }

                    history.addItem(stringContent, contentType: .text, rtfContent: rtfBase64)
                }
            }
        }
    }
}

// MARK: - Menu Bar Manager

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

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipboardManager")
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

// MARK: - Global Keyboard Shortcut Handler

class GlobalShortcutHandler {
    private var eventMonitor: Any?
    weak var history: ClipboardHistory?
    weak var appDelegate: AppDelegate?

    init(history: ClipboardHistory, appDelegate: AppDelegate) {
        self.history = history
        self.appDelegate = appDelegate
        setupGlobalShortcuts()
    }

    private func setupGlobalShortcuts() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
    }

    private func handleGlobalKeyEvent(_ event: NSEvent) {
        // Only handle if Cmd+Option is pressed
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdAltPressed = modifiers.contains([.command, .option])

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

// MARK: - Custom Window Class

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

// MARK: - Window Delegate

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

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions options: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        return options
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    var menuBarManager: MenuBarManager?
    var shortcutHandler: GlobalShortcutHandler?
    var windowDelegate: MenuBarWindowDelegate?
    var localEventMonitor: Any?
    weak var history: ClipboardHistory?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hide dock icon as early as possible
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        if let history = history {
            menuBarManager = MenuBarManager(history: history, appDelegate: self)
            shortcutHandler = GlobalShortcutHandler(history: history, appDelegate: self)
        }

        // Setup window delegate for all windows - do this after a small delay to ensure windows are ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupWindowBehavior()
        }
    }

    func applyWindowBehavior(to window: NSWindow) {
        configureWindow(window)
    }

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
        NotificationCenter.default.addObserver(forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main) { [weak self] note in
            if let w = note.object as? NSWindow {
                w.orderOut(nil)
                self?.mainWindow = w
            }
        }

        // Store reference
        self.mainWindow = window
    }

    @objc private func handleMiniaturizeButton(_ sender: Any?) {
        if let window = self.mainWindow {
            window.orderOut(nil)
        }
    }

    @objc func toggleMainWindow() {
        if let window = mainWindow, window.isVisible {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    @objc func showMainWindow() {
        // Find the main window from the app's windows
        if let window = NSApp.windows.first(where: { !$0.isKind(of: NSPanel.self) }) {
            configureWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.mainWindow = window
        }
    }
}

// MARK: - UI Views

struct ContentView: View {
    @EnvironmentObject var history: ClipboardHistory
    @State private var searchText = ""

    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return history.items
        }
        return history.items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor).ignoresSafeArea()
                .background(WindowAccessor { window in
                    // Ensure our AppKit configuration is applied to the exact SwiftUI window
                    if let app = NSApp.delegate as? AppDelegate {
                        app.applyWindowBehavior(to: window)
                    }
                })

            VStack(spacing: 0) {
                // Header with title
                VStack(alignment: .leading, spacing: 12) {
                    Text("Clipboard History")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)

                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding(16)

                // Content
                if filteredItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 56))
                            .foregroundColor(.secondary)

                        Text("No items yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Copy something to get started")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(filteredItems) { item in
                                ClipboardItemRow(item: item, history: history)
                            }
                        }
                        .padding(12)
                    }
                }

                // Footer
                HStack(spacing: 12) {
                    Button(action: {
                        history.clearHistory()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Clear All")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("k", modifiers: [.command, .shift])

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(history.items.count) items")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .borderTop()
            }
        }
        .frame(minWidth: 420, minHeight: 350)
    }
}

// MARK: - Helper Extensions

extension View {
    func borderTop() -> some View {
        self.overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Window Accessor

final class _WindowDetectorView: NSView {
    var onResolve: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = self.window {
            onResolve?(w)
            // Run once
            onResolve = nil
        }
    }
}

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

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let history: ClipboardHistory
    @State private var isHovered = false

    var contentIcon: String {
        switch item.contentType {
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .url:
            return "link"
        case .file:
            return "doc"
        }
    }

    var iconColor: Color {
        switch item.contentType {
        case .text:
            return .blue
        case .image:
            return .purple
        case .url:
            return .orange
        case .file:
            return .green
        }
    }

    var contentPreview: String {
        switch item.contentType {
        case .text:
            return item.content.count > 100 ? String(item.content.prefix(100)) + "..." : item.content
        case .image:
            return "[Image]"
        case .url:
            return item.content
        case .file:
            return item.filename ?? "[File]"
        }
    }

    var contentTypeLabel: String {
        switch item.contentType {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .url:
            return "Link"
        case .file:
            return "File"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                    Image(systemName: contentIcon)
                        .foregroundColor(iconColor)
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(width: 36, height: 36)

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(contentPreview)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    HStack(spacing: 8) {
                        Text(contentTypeLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(4)

                        Text(item.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: {
                        pasteItem()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Paste to clipboard")
                    .opacity(isHovered ? 1 : 0.6)

                    Button(action: {
                        history.togglePin(for: item)
                    }) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(item.isPinned ? .orange : .secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "Unpin" : "Pin")
                    .opacity(isHovered ? 1 : 0.6)
                }
            }
            .padding(12)
        }
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
    }

    private func pasteItem() {
        NSPasteboard.general.clearContents()

        switch item.contentType {
        case .text, .url:
            NSPasteboard.general.setString(item.content, forType: .string)

            // Restore RTF formatting if available
            if let rtfBase64 = item.rtfContent, let rtfData = Data(base64Encoded: rtfBase64) {
                NSPasteboard.general.setData(rtfData, forType: .rtf)
            }
        case .image:
            if let data = Data(base64Encoded: item.content),
               let image = NSImage(data: data) {
                NSPasteboard.general.writeObjects([image])
            }
        case .file:
            NSPasteboard.general.setString(item.content, forType: .string)
        }
    }
}

// MARK: - App

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
