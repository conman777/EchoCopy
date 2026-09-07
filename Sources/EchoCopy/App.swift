import SwiftUI
import AppKit
import Foundation
import Combine
import ApplicationServices
import Carbon.HIToolbox
import ImageIO
import OSLog
import UniformTypeIdentifiers
import Darwin

// MARK: - Data Models

enum ContentType: String, Codable, Sendable {
    case text
    case image
    case file
    case url
}

struct ClipboardItem: Codable, Identifiable, Sendable {
    let id: UUID
    let content: String  // Plain text, URL, or base64 for images
    let contentType: ContentType
    let timestamp: Date
    let isPinned: Bool
    let filename: String?  // For file/image references
    let rtfContent: String?  // Rich Text Format (base64 encoded)

    init(
        id: UUID = UUID(),
        content: String,
        contentType: ContentType = .text,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        filename: String? = nil,
        rtfContent: String? = nil
    ) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.filename = filename
        self.rtfContent = rtfContent
    }

    var searchableText: String {
        switch contentType {
        case .text, .url:
            return content
        case .image:
            return filename ?? ""
        case .file:
            return filename ?? content
        }
    }

    var menuPreview: String {
        switch contentType {
        case .text:
            let trimmed = boundedPreview(
                characterLimit: 46,
                stopsAtFirstNewline: true
            )
            return trimmed.isEmpty ? "Text" : trimmed
        case .image:
            return filename ?? "Image"
        case .url:
            if let url = URL(string: content), let host = url.host, !host.isEmpty {
                return host
            }
            return content
        case .file:
            return filename ?? "File"
        }
    }

    /// Keeps SwiftUI labels from materializing an entire megabyte-sized
    /// clipboard string when a row only displays a single short line.
    var listPreview: String {
        switch contentType {
        case .text:
            let preview = boundedPreview(
                characterLimit: 240,
                stopsAtFirstNewline: false
            )
            return preview.isEmpty ? "Text" : preview
        case .image:
            return filename ?? "Image"
        case .url:
            return boundedPreview(characterLimit: 240, stopsAtFirstNewline: true)
        case .file:
            return filename ?? boundedPreview(
                characterLimit: 240,
                stopsAtFirstNewline: true
            )
        }
    }

    private func boundedPreview(
        characterLimit: Int,
        stopsAtFirstNewline: Bool
    ) -> String {
        guard characterLimit > 0 else { return "" }

        var preview = String()
        preview.reserveCapacity(min(characterLimit, 256))
        var appendedCharacters = 0

        for character in content {
            if character.isNewline {
                if stopsAtFirstNewline {
                    break
                }
                if preview.last != " " {
                    preview.append(" ")
                    appendedCharacters += 1
                }
            } else {
                preview.append(character)
                appendedCharacters += 1
            }

            if appendedCharacters >= characterLimit {
                break
            }
        }

        return preview.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
class ClipboardHistory: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var excludedApps: Set<String> = []
    @Published private(set) var persistenceError: String?
    @Published private(set) var canRetryHistoryUnlock = false
    var isPersistenceBlocked: Bool { persistenceBlocked }
    private let maxItems = 500
    private let excludedAppsKey = "excludedApps"
    private let defaultExclusionsVersionKey = "defaultExclusionsVersion"
    private let defaultExclusionsVersion = 1
    private let keychainRepairMessage = "EchoCopy needs a one-time Keychain repair. Choose Repair Secure History."
    private let historyStore: EncryptedHistoryStore
    private let persistenceCoordinator: HistoryPersistenceCoordinator
    private var persistenceGeneration = 0
    private var persistenceBlocked = false
    private var hasLoadedHistory = false
    private let defaultExcludedApps: Set<String> = [
        "com.1password.1password",           // 1Password
        "com.agilebits.onepassword7",        // 1Password 7
        "com.lastpass.LastPass",             // LastPass
        "com.bitwarden.desktop",             // Bitwarden
        "com.dashlane.Dashlane",             // Dashlane
        "com.keeper.KeeperPasswordManager",  // Keeper
        "com.nordpass.NordPass",             // NordPass
        "com.apple.keychainaccess",          // Keychain Access
        "com.apple.Passwords",               // Passwords (macOS 14+)
        "com.apple.passwords"                // Passwords (alternate identifier)
    ]

    init(historyStore: EncryptedHistoryStore = .live()) {
        self.historyStore = historyStore
        self.persistenceCoordinator = HistoryPersistenceCoordinator(historyStore: historyStore)
        loadHistory()
        loadExcludedApps()
    }

    func addItem(_ content: String, contentType: ContentType = .text, filename: String? = nil, rtfContent: String? = nil) {
        guard ClipboardPolicy.acceptsStoredItem(
            content: content,
            contentType: contentType,
            rtfContent: rtfContent,
            filename: filename
        ) else {
            return
        }

        insertItem(
            ClipboardItem(
                content: content,
                contentType: contentType,
                filename: filename,
                rtfContent: rtfContent
            )
        )
    }

    /// Inserts a payload that was already validated on the clipboard processing
    /// queue. This avoids decoding large base64 image/RTF values again on MainActor.
    func addPreparedItem(
        _ content: String,
        contentType: ContentType,
        filename: String? = nil,
        rtfContent: String? = nil
    ) {
        insertItem(
            ClipboardItem(
                content: content,
                contentType: contentType,
                filename: filename,
                rtfContent: rtfContent
            )
        )
    }

    private func insertItem(_ newItem: ClipboardItem) {

        // Compare against the most recent *unpinned* item (pinned items are kept at the top).
        if let lastItem = items.first(where: { !$0.isPinned }),
           lastItem.content == newItem.content,
           lastItem.contentType == newItem.contentType,
           lastItem.filename == newItem.filename,
           lastItem.rtfContent == newItem.rtfContent {
            return
        }

        // Keep pinned items at the top; insert new history items just below pinned.
        let insertionIndex = items.firstIndex(where: { !$0.isPinned }) ?? items.count
        items.insert(newItem, at: insertionIndex)

        if items.count > maxItems {
            // Prefer dropping the oldest unpinned items first (keep pinned if possible).
            while items.count > maxItems {
                if let lastUnpinnedIndex = items.lastIndex(where: { !$0.isPinned }) {
                    items.remove(at: lastUnpinnedIndex)
                } else {
                    items.removeLast()
                }
            }
        }

        scheduleHistorySave()
    }

    func removeItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        scheduleHistorySave()
    }

    func togglePin(for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        let current = items.remove(at: index)
        let updated = ClipboardItem(
            id: current.id,
            content: current.content,
            contentType: current.contentType,
            timestamp: current.timestamp,
            isPinned: !current.isPinned,
            filename: current.filename,
            rtfContent: current.rtfContent
        )

        if updated.isPinned {
            // Newly pinned items go to the very top.
            items.insert(updated, at: 0)
        } else {
            // Return unpinned items to the unpinned section, keeping chronological ordering by timestamp.
            let insertionIndex = insertionIndexForUnpinnedItem(with: updated.timestamp)
            items.insert(updated, at: insertionIndex)
        }

        scheduleHistorySave()
    }

    func clearHistory() {
        items.removeAll()
        scheduleHistorySave()
    }

    func clearUnpinnedHistory() {
        items.removeAll(where: { !$0.isPinned })
        scheduleHistorySave()
    }

    private func insertionIndexForUnpinnedItem(with timestamp: Date) -> Int {
        let startIndex = items.firstIndex(where: { !$0.isPinned }) ?? items.count
        guard startIndex < items.count else { return items.count }

        for i in startIndex..<items.count {
            if items[i].timestamp < timestamp {
                return i
            }
        }
        return items.count
    }

    private func scheduleHistorySave() {
        guard !persistenceBlocked else { return }

        persistenceGeneration &+= 1
        let generation = persistenceGeneration

        persistenceCoordinator.scheduleSave(items, generation: generation) { [weak self] completedGeneration, result in
            Task { @MainActor [weak self] in
                self?.handlePersistenceResult(
                    generation: completedGeneration,
                    result: result
                )
            }
        }
    }

    private func handlePersistenceResult(
        generation: Int,
        result: Result<[ClipboardItem], Error>
    ) {
        guard generation == persistenceGeneration else { return }

        switch result {
        case .success(let persistedItems):
            if persistedItems.map(\.id) != items.map(\.id) {
                items = persistedItems
            }
            persistenceBlocked = false
            canRetryHistoryUnlock = false
            persistenceError = nil
        case .failure(let error):
            let requiresUnlock = (error as? EncryptedHistoryStoreError)?.requiresKeychainUnlock ?? false
            if requiresUnlock {
                historyStore.recordKeychainRepairRequired()
            }
            persistenceBlocked = requiresUnlock
            canRetryHistoryUnlock = requiresUnlock
            persistenceError = requiresUnlock
                ? keychainRepairMessage
                : "Clipboard history could not be saved securely."
        }
    }

    func flushPersistence() {
        guard !persistenceBlocked else { return }

        persistenceGeneration &+= 1
        let generation = persistenceGeneration
        let result = persistenceCoordinator.flushSave(items)
        handlePersistenceResult(generation: generation, result: result)
    }

    private func loadHistory() {
        if historyStore.requiresUserInitiatedKeychainRepair {
            // Preserve the unreadable encrypted payload for optional manual
            // recovery, then start clean. Normal startup must never touch a
            // legacy Keychain item or block new clipboard history.
            historyStore.archiveLegacyHistoryAndStartFresh()
        }

        loadHistory(
            allowKeychainInteraction: false,
            preserveItemsOnFailure: false
        )
    }

    /// Retries the protected history read only after the user explicitly asks
    /// EchoCopy to unlock its Keychain item. This keeps startup silent while
    /// ensuring any authentication prompt names EchoCopy, not a helper tool.
    func retryHistoryUnlock() {
        guard canRetryHistoryUnlock else { return }

        loadHistory(
            allowKeychainInteraction: true,
            preserveItemsOnFailure: true
        )
    }

    private func loadHistory(
        allowKeychainInteraction: Bool,
        preserveItemsOnFailure: Bool
    ) {
        do {
            guard let decoded = try historyStore.load(
                maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes,
                allowKeychainInteraction: allowKeychainInteraction
            ) else {
                persistenceBlocked = false
                canRetryHistoryUnlock = false
                persistenceError = nil
                hasLoadedHistory = true
                if !items.isEmpty { scheduleHistorySave() }
                return
            }

            let sanitizedItems = decoded.filter {
                ClipboardPolicy.acceptsStoredItem(
                    content: $0.content,
                    contentType: $0.contentType,
                    rtfContent: $0.rtfContent,
                    filename: $0.filename
                )
            }
            let sessionItems = items
            if preserveItemsOnFailure {
                if !hasLoadedHistory {
                    // Keep session edits when an item also exists on disk.
                    let sessionIDs = Set(sessionItems.map(\.id))
                    let merged = sessionItems + sanitizedItems.filter { !sessionIDs.contains($0.id) }
                    items = merged.filter(\.isPinned)
                        + merged.filter { !$0.isPinned }.sorted { $0.timestamp > $1.timestamp }
                }
                // After a save failure, memory already contains the full history,
                // including deletions. Do not restore the older disk snapshot.
            } else {
                items = sanitizedItems
            }
            enforceItemCountLimit()
            hasLoadedHistory = true
            persistenceBlocked = false
            canRetryHistoryUnlock = false
            persistenceError = nil
            if items.map(\.id) != decoded.map(\.id) || !sessionItems.isEmpty {
                scheduleHistorySave()
            }
        } catch {
            if !preserveItemsOnFailure {
                items = []
            }
            let requiresUnlock = (error as? EncryptedHistoryStoreError)?.requiresKeychainUnlock ?? false
            if requiresUnlock {
                historyStore.recordKeychainRepairRequired()
            }
            persistenceBlocked = true
            canRetryHistoryUnlock = requiresUnlock
            persistenceError = requiresUnlock
                ? keychainRepairMessage
                : "Secure clipboard history could not be opened. EchoCopy will not overwrite it."
        }
    }

    private func enforceItemCountLimit() {
        while items.count > maxItems {
            let indexToRemove = items.lastIndex(where: { !$0.isPinned }) ?? items.count - 1
            items.remove(at: indexToRemove)
        }
    }

    private func loadExcludedApps() {
        let hasMigratedDefaults = UserDefaults.standard.integer(forKey: defaultExclusionsVersionKey) >= defaultExclusionsVersion

        if let saved = UserDefaults.standard.array(forKey: excludedAppsKey) as? [String] {
            let savedApps = Set(saved)
            excludedApps = hasMigratedDefaults ? savedApps : savedApps.union(defaultExcludedApps)
            if excludedApps != savedApps || !hasMigratedDefaults {
                saveExcludedApps()
            }
        } else {
            excludedApps = defaultExcludedApps
            saveExcludedApps()
        }

        if !hasMigratedDefaults {
            UserDefaults.standard.set(defaultExclusionsVersion, forKey: defaultExclusionsVersionKey)
        }
    }

    private func saveExcludedApps() {
        UserDefaults.standard.set(Array(excludedApps), forKey: excludedAppsKey)
    }

    func addExcludedApp(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate bundle ID format and prevent adding this app
        guard !trimmed.isEmpty,
              trimmed.contains("."),
              trimmed != Bundle.main.bundleIdentifier else {
            return
        }
        excludedApps.insert(trimmed)
        saveExcludedApps()
    }

    func removeExcludedApp(_ bundleID: String) {
        excludedApps.remove(bundleID)
        saveExcludedApps()
    }

    func isAppExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return excludedApps.contains(bundleID)
    }
}

// MARK: - Clipboard Monitoring

@MainActor
class ClipboardMonitor {
    private var timer: Timer?
    private var applicationActivationObserver: NSObjectProtocol?
    private var lastChangeCount: Int = 0
    private var lastObservedFrontmostBundleID: String?
    private let history: ClipboardHistory
    private let writeTracker: PasteboardWriteTracker
    private let screenshotCoordinator: ScreenshotCaptureCoordinator
    private let processingQueue = DispatchQueue(
        label: "com.yourcompany.echocopy.clipboard-processing",
        qos: .utility
    )
    private let checkInterval: TimeInterval = 0.5
    private let timerTolerance: TimeInterval = 0.2

    init(
        history: ClipboardHistory,
        writeTracker: PasteboardWriteTracker = .shared,
        screenshotCoordinator: ScreenshotCaptureCoordinator = .shared
    ) {
        self.history = history
        self.writeTracker = writeTracker
        self.screenshotCoordinator = screenshotCoordinator
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.lastObservedFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func start() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkClipboard()
            }
        }
        timer.tolerance = timerTolerance
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer

        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                return
            }
            MainActor.assumeIsolated {
                self?.checkClipboard(observedApplication: application)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                applicationActivationObserver
            )
            self.applicationActivationObserver = nil
        }
    }

    private func checkClipboard(observedApplication: NSRunningApplication? = nil) {
        let currentChangeCount = NSPasteboard.general.changeCount

        // App activation notifications maintain source-app context without an
        // NSWorkspace query on every idle timer tick. They also let a copy be
        // processed immediately when the user switches apps.
        guard currentChangeCount != lastChangeCount else {
            if let observedApplication {
                lastObservedFrontmostBundleID = observedApplication.bundleIdentifier
            }
            return
        }

        let currentBundleID = observedApplication?.bundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let previouslyObservedBundleID = lastObservedFrontmostBundleID
        lastObservedFrontmostBundleID = currentBundleID
        lastChangeCount = currentChangeCount

        // EchoCopy deliberately changed the pasteboard. Do not feed that write
        // back into history and trigger another encryption/save cycle.
        guard !writeTracker.consumeIfInternal(changeCount: currentChangeCount) else {
            return
        }

        let pasteboard = NSPasteboard.general
        let pasteboardTypeIdentifiers = pasteboard.types?.map(\.rawValue) ?? []
        guard !ClipboardPolicy.containsSuppressedPasteboardType(pasteboardTypeIdentifiers) else {
            screenshotCoordinator.cancelIfPasteboardChanged(to: currentChangeCount)
            return
        }

        // NSPasteboard does not provide a trustworthy source application. The
        // previous/current apps bracket the copy event. Allow transitions only
        // when both apps are known and neither is excluded; this catches a fast
        // copy-then-switch back to EchoCopy without leaking content across a
        // password manager. A user-initiated screenshot remains a special case.
        let sourceIsExcluded = currentBundleID.map(history.isAppExcluded) ?? false
        let ordinarySourceCanBeStored = ClipboardPolicy.canStoreClipboardChange(
            previousBundleID: previouslyObservedBundleID,
            currentBundleID: currentBundleID,
            excludedBundleIDs: history.excludedApps
        )
        let isAwaitingScreenshot = screenshotCoordinator.isAwaitingScreenshot(
            pasteboardChangeCount: currentChangeCount
        )

        // Check for image FIRST (images often come with URLs, so check images before URLs).
        // Reject oversized source data before asking AppKit to decode it.
        let imageTypes: [(type: NSPasteboard.PasteboardType, filename: String)] = [
            (.png, "image.png"),
            (NSPasteboard.PasteboardType("public.jpeg"), "image.jpg"),
            (.tiff, "image.tiff")
        ]

        var selectedImage: (data: Data, filename: String)?
        for candidate in imageTypes {
            guard let data = pasteboard.data(forType: candidate.type) else { continue }

            let isWithinLimit = isAwaitingScreenshot
                ? data.count <= ClipboardPolicy.maxScreenshotSourceBytes
                : ClipboardPolicy.acceptsImagePasteboardData(byteCount: data.count)
            if isWithinLimit {
                selectedImage = (data, candidate.filename)
                break
            }
        }

        if let selectedImage,
           ordinarySourceCanBeStored || isAwaitingScreenshot {
            let screenshotSaveRequest = isAwaitingScreenshot
                ? screenshotCoordinator.consumeScreenshot(
                    pasteboardChangeCount: currentChangeCount
                )
                : nil

            prepareImageForHistory(
                selectedImage.data,
                filename: selectedImage.filename,
                screenshotSaveRequest: screenshotSaveRequest,
                shouldAddToHistory: ordinarySourceCanBeStored
                    || (isAwaitingScreenshot && !sourceIsExcluded)
            )
            return
        }

        if isAwaitingScreenshot {
            // The first post-shortcut pasteboard change was not a usable image;
            // do not mistake a later, unrelated copied image for the screenshot.
            screenshotCoordinator.cancelIfPasteboardChanged(to: currentChangeCount)
        }

        guard ordinarySourceCanBeStored else { return }

        // Check for URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL],
           let url = urls.first {
            let fileURL = url as URL
            history.addItem(
                fileURL.absoluteString,
                contentType: fileURL.isFileURL ? .file : .url,
                filename: fileURL.isFileURL ? fileURL.lastPathComponent : nil
            )
            return
        }

        // Check for text with RTF support.
        if let stringContent = pasteboard.string(forType: .string),
           !stringContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let rtfData = pasteboard.data(forType: .rtf) {
                guard ClipboardPolicy.acceptsRTFPasteboardData(byteCount: rtfData.count) else {
                    return
                }
                prepareTextForHistory(stringContent, rtfData: rtfData)
            } else {
                history.addItem(stringContent, contentType: .text)
            }
        }
    }

    private func prepareImageForHistory(
        _ imageData: Data,
        filename: String,
        screenshotSaveRequest: ScreenshotSaveRequest? = nil,
        shouldAddToHistory: Bool = true
    ) {
        processingQueue.async { [weak self] in
            guard let self,
                  CGImageSourceCreateWithData(imageData as CFData, nil) != nil else {
                return
            }

            let savedScreenshot = screenshotSaveRequest.flatMap {
                ScreenshotFileSaver.save(imageData: imageData, request: $0)
            }
            guard shouldAddToHistory else { return }

            let preparedImageData = savedScreenshot?.imageData ?? imageData
            let preparedFilename = savedScreenshot?.fileURL.lastPathComponent ?? filename
            let base64 = preparedImageData.base64EncodedString()
            guard ClipboardPolicy.acceptsStoredItem(
                content: base64,
                contentType: .image,
                rtfContent: nil,
                filename: preparedFilename
            ) else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.history.addPreparedItem(
                    base64,
                    contentType: .image,
                    filename: preparedFilename
                )
            }
        }
    }

    private func prepareTextForHistory(_ text: String, rtfData: Data) {
        processingQueue.async { [weak self] in
            let rtfBase64 = rtfData.base64EncodedString()
            guard ClipboardPolicy.acceptsStoredItem(
                content: text,
                contentType: .text,
                rtfContent: rtfBase64
            ) else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.history.addPreparedItem(
                    text,
                    contentType: .text,
                    rtfContent: rtfBase64
                )
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                applicationActivationObserver
            )
        }
    }
}

// MARK: - Menu Bar Manager

struct MenuBarHistoryView: View {
    @ObservedObject var history: ClipboardHistory
    let onPaste: (ClipboardItem) -> Void
    let onOpenWindow: () -> Void
    let onPrepareForSettings: () -> Void
    let onQuit: () -> Void

    static let width: CGFloat = 360
    static let rowHeight: CGFloat = 24
    static let separatorHeight: CGFloat = 1
    static let footerHeight: CGFloat = 34

    private var orderedItems: [ClipboardItem] {
        MenuBarHistoryPresentation.orderedItems(history.items)
    }

    static func contentHeight(for itemCount: Int) -> CGFloat {
        let rowCount = max(
            1,
            MenuBarHistoryPresentation.visibleRowCount(for: itemCount)
        )
        return CGFloat(rowCount) * rowHeight + separatorHeight + footerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            if orderedItems.isEmpty {
                Text("Clipboard history is empty")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.rowHeight)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                            Button {
                                onPaste(item)
                            } label: {
                                MenuBarHistoryRow(item: item, index: index)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Pastes this item into the previous app")
                        }
                    }
                }
                .frame(
                    height: CGFloat(
                        MenuBarHistoryPresentation.visibleRowCount(
                            for: orderedItems.count
                        )
                    ) * Self.rowHeight
                )
            }

            Divider()

            HStack(spacing: 12) {
                Button("Open EchoCopy", action: onOpenWindow)
                    .buttonStyle(.plain)
                    .fontWeight(.medium)

                Spacer(minLength: 8)

                Button("Clear") {
                    history.clearUnpinnedHistory()
                }
                .buttonStyle(.plain)
                .disabled(!history.items.contains { !$0.isPinned })
                .help("Clear history except pinned items")
                .accessibilityHint("Removes all history items except pinned items")

                SettingsButton(beforeOpen: onPrepareForSettings) {
                    Text("Settings")
                }
                .buttonStyle(.plain)

                Button("Quit", action: onQuit)
                    .buttonStyle(.plain)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .frame(height: Self.footerHeight)
        }
        .frame(
            width: Self.width,
            height: Self.contentHeight(for: orderedItems.count)
        )
    }
}

struct MenuBarHistoryRow: View {
    let item: ClipboardItem
    let index: Int
    @State private var isHovered = false

    private var preview: String {
        let flattened = item.menuPreview
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = flattened.isEmpty ? "Item" : flattened
        return value.count > 45
            ? String(value.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            : value
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(index + 1). \(preview)")
                .font(.system(size: 13))
                .foregroundColor(isHovered ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: MenuBarHistoryView.rowHeight)
        .frame(maxWidth: .infinity)
        .background(isHovered ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(index + 1). \(preview)")
    }
}

@MainActor
class MenuBarManager: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var history: ClipboardHistory?
    private weak var appDelegate: AppDelegate?
    private var historySubscription: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?

    init(history: ClipboardHistory, appDelegate: AppDelegate) {
        self.history = history
        self.appDelegate = appDelegate
        super.init()
        setupMenuBar()
        setupPopover(history: history)
        observeHistorySize()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "EchoCopy") {
                button.image = image
            } else {
                // Keep the item discoverable on systems without this SF Symbol.
                button.title = "EchoCopy"
            }
            button.toolTip = "EchoCopy"
            button.setAccessibilityLabel("EchoCopy")
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
        }
    }

    private func setupPopover(history: ClipboardHistory) {
        let content = MenuBarHistoryView(
            history: history,
            onPaste: { [weak self] item in
                self?.closePopover()
                self?.appDelegate?.pasteHistoryItem(item)
            },
            onOpenWindow: { [weak self] in
                self?.closePopover()
                self?.appDelegate?.showMainWindow()
            },
            onPrepareForSettings: { [weak self] in
                self?.closePopover()
            },
            onQuit: { [weak self] in
                self?.closePopover()
                NSApp.terminate(nil)
            }
        )

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: content)
        updatePopoverSize(for: history.items.count)
    }

    private func observeHistorySize() {
        historySubscription = history?.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.updatePopoverSize(for: items.count)
            }
    }

    private func updatePopoverSize(for itemCount: Int) {
        popover.contentSize = NSSize(
            width: MenuBarHistoryView.width,
            height: MenuBarHistoryView.contentHeight(for: itemCount)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
            return
        }

        appDelegate?.prepareForHistoryInteraction()
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidShow(_ notification: Notification) {
        stopMonitoringClicks()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Accessory apps can show a popover without becoming active, so
        // transient behavior alone does not reliably dismiss outside clicks.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePopover()
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                if event.window !== self.popover.contentViewController?.view.window,
                   event.window !== self.statusItem?.button?.window {
                    self.closePopover()
                }
                return event
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitoringClicks()
    }

    private func stopMonitoringClicks() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    }
}

// MARK: - Global Keyboard Shortcut Handler

class GlobalShortcutHandler {
    private static let logger = Logger(
        subsystem: "com.yourcompany.echocopy",
        category: "GlobalShortcutHandler"
    )

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var defaultsObserver: NSObjectProtocol?
    private var swallowedScreenshotKeyCodes = Set<CGKeyCode>()
    private var eventTapRetryWorkItem: DispatchWorkItem?
    private var eventTapRetryAttempt = 0
    private var lastLoggedAccessibilityTrust: Bool?
    private let screenshotCoordinator: ScreenshotCaptureCoordinator
    weak var appDelegate: AppDelegate?

    init(
        appDelegate: AppDelegate,
        screenshotCoordinator: ScreenshotCaptureCoordinator = .shared
    ) {
        self.appDelegate = appDelegate
        self.screenshotCoordinator = screenshotCoordinator
        setupGlobalShortcuts()
    }

    private func setupGlobalShortcuts() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshConfiguration()
        }
        refreshConfiguration()
    }

    func refreshConfiguration() {
        eventTapRetryWorkItem?.cancel()
        eventTapRetryWorkItem = nil
        eventTapRetryAttempt = 0
        applyConfiguration()
    }

    private func applyConfiguration() {
        // Isolated UI smoke tests do not need global shortcuts and must not
        // trigger a system Accessibility permission prompt.
        if ProcessInfo.processInfo.environment["ECHOCOPY_DISABLE_GLOBAL_SHORTCUTS"] == "1" {
            uninstallEventTap()
            return
        }

        let trusted = AXIsProcessTrusted()
        let delegate = appDelegate
        Task { @MainActor [weak delegate] in
            delegate?.updateAccessibilityStatus(trusted)
        }
        if lastLoggedAccessibilityTrust != trusted {
            lastLoggedAccessibilityTrust = trusted
            Self.logger.notice(
                "Accessibility trust reported by EchoCopy: \(trusted, privacy: .public)"
            )
        }

        guard ScreenshotShortcutRuntimePolicy.shouldInstallEventTap(
            automaticCaptureEnabled: screenshotCoordinator.isAutomaticClipboardCaptureEnabled,
            accessibilityTrusted: trusted
        ) else {
            uninstallEventTap()
            return
        }

        installEventTap()
    }

    private func installEventTap() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let handler = Unmanaged<GlobalShortcutHandler>
                .fromOpaque(refcon)
                .takeUnretainedValue()

            return handler.handleEventTap(proxy: proxy, type: type, event: event)
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let tapLocations: [(location: CGEventTapLocation, name: String)] = [
            (.cghidEventTap, "HID"),
            (.cgSessionEventTap, "session")
        ]
        var installedTap: CFMachPort?
        var installedTapName: String?

        for candidate in tapLocations {
            if let tap = CGEvent.tapCreate(
                tap: candidate.location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: userInfo
            ) {
                installedTap = tap
                installedTapName = candidate.name
                break
            }
        }

        guard let tap = installedTap else {
            Self.logger.error("Active keyboard event tap could not be installed")
            scheduleEventTapRetry()
            return
        }

        Self.logger.notice(
            "Active keyboard event tap installed at \(installedTapName ?? "unknown", privacy: .public)"
        )

        eventTapRetryWorkItem?.cancel()
        eventTapRetryWorkItem = nil
        eventTapRetryAttempt = 0
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func scheduleEventTapRetry() {
        let retryDelays: [TimeInterval] = [1, 4, 15]
        guard eventTapRetryWorkItem == nil,
              eventTapRetryAttempt < retryDelays.count else {
            return
        }

        let delay = retryDelays[eventTapRetryAttempt]
        eventTapRetryAttempt += 1
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.eventTapRetryWorkItem = nil
            self.applyConfiguration()
        }
        eventTapRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func uninstallEventTap() {
        eventTapRetryWorkItem?.cancel()
        eventTapRetryWorkItem = nil

        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            eventTapSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        swallowedScreenshotKeyCodes.removeAll(keepingCapacity: false)
    }

    private func handleEventTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the system disables the tap, re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if ScreenshotShortcutRemapper.isSyntheticScreenshotEvent(event) {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            if swallowedScreenshotKeyCodes.remove(keyCode) != nil {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if keyCode == CGKeyCode(kVK_Escape) {
            screenshotCoordinator.cancelPendingCapture()
        }

        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isAutoRepeat,
           ScreenshotShortcutPolicy.isStandardScreenshotShortcut(
               keyCode: keyCode,
               flags: flags
           ) {
            guard ScreenshotClipboardShortcutConfiguration.isEnabled(
                for: keyCode
            ) else {
                Self.logger.error(
                    "Clipboard screenshot shortcut is unavailable for key code \(keyCode, privacy: .public); preserving the original event"
                )
                return Unmanaged.passUnretained(event)
            }

            guard screenshotCoordinator.beginAutomaticClipboardCapture(
                startingPasteboardChangeCount: NSPasteboard.general.changeCount
            ) else {
                return Unmanaged.passUnretained(event)
            }

            guard let replacement =
                    ScreenshotShortcutRemapper.makeClipboardShortcutReplacement(
                        keyCode: keyCode,
                        flags: flags
                    ) else {
                screenshotCoordinator.cancelPendingCapture()
                return Unmanaged.passUnretained(event)
            }

            swallowedScreenshotKeyCodes.insert(keyCode)
            for replacementEvent in replacement.events {
                replacementEvent.post(tap: .cghidEventTap)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        eventTapRetryWorkItem?.cancel()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        uninstallEventTap()
    }
}

// MARK: - Custom Window Class

class MenuBarWindow: NSWindow {
    override func miniaturize(_ sender: Any?) {
        // Release the history UI instead of retaining a hidden window.
        close()
    }

    override func performMiniaturize(_ sender: Any?) {
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command && event.charactersIgnoringModifiers == "m" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Window Delegate

class MenuBarWindowDelegate: NSObject, NSWindowDelegate {
    var onWindowClosed: ((NSWindow) -> Void)?

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            window.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            onWindowClosed?(window)
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var accessibilityTrusted = true
    var mainWindow: NSWindow?
    var menuBarManager: MenuBarManager?
    var shortcutHandler: GlobalShortcutHandler?
    var windowDelegate: MenuBarWindowDelegate?
    weak var history: ClipboardHistory?
    private weak var lastExternalApplication: NSRunningApplication?
    private var hasAppliedPreferredSize = false
    private var memoryReliefWorkItem: DispatchWorkItem?

    func updateAccessibilityStatus(_ trusted: Bool) {
        if accessibilityTrusted != trusted {
            accessibilityTrusted = trusted
        }
    }

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    func revealCurrentAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hide dock icon as early as possible
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let history = history else {
            print("Warning: ClipboardHistory not initialized")
            return
        }

        rememberCurrentExternalApplication()

        menuBarManager = MenuBarManager(history: history, appDelegate: self)
        shortcutHandler = GlobalShortcutHandler(appDelegate: self)
    }

    func applicationWillTerminate(_ notification: Notification) {
        memoryReliefWorkItem?.cancel()
        // Persist the latest coalesced snapshot before an orderly quit.
        history?.flushPersistence()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Accessibility changes are applied when the user returns from System
        // Settings, with no perpetual permission polling while EchoCopy idles.
        shortcutHandler?.refreshConfiguration()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applyWindowBehavior(to window: NSWindow) {
        configureWindow(window)
    }

    private func configureWindow(_ window: NSWindow) {
        if windowDelegate == nil {
            let delegate = MenuBarWindowDelegate()
            delegate.onWindowClosed = { [weak self] closedWindow in
                guard let self else { return }
                if self.mainWindow === closedWindow {
                    self.mainWindow = nil
                }
                self.releaseClosedWindowResources()
            }
            windowDelegate = delegate
        }

        window.delegate = windowDelegate
        window.hidesOnDeactivate = true
        window.level = .floating

        var collectionBehavior = window.collectionBehavior
        collectionBehavior.insert(.canJoinAllSpaces)
        collectionBehavior.insert(.fullScreenAuxiliary)
        collectionBehavior.insert(.transient)
        window.collectionBehavior = collectionBehavior

        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Remove Dock minimization entirely
        window.styleMask.remove(.miniaturizable)
        // AppDelegate owns the window through `mainWindow`. Under Swift ARC,
        // AppKit's legacy self-release-on-close behavior would add a second
        // release after `windowWillClose` clears that strong reference.
        window.isReleasedWhenClosed = false

        self.mainWindow = window

        window.minSize = NSSize(width: 320, height: 400)
        window.maxSize = NSSize(width: 520, height: 860)

        if !hasAppliedPreferredSize {
            let preferredContentSize = NSSize(width: 400, height: 560)
            window.setContentSize(preferredContentSize)
            hasAppliedPreferredSize = true
        }
    }

    private func releaseClosedWindowResources() {
        ClipboardThumbnailCache.shared.removeAll()

        memoryReliefWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            // Large image/history buffers are temporary. Once SwiftUI releases
            // the closed window's view state, return its unused pages
            // to macOS instead of retaining the allocator's high-water mark.
            malloc_zone_pressure_relief(nil, 0)
        }
        memoryReliefWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 0.5,
            execute: workItem
        )
    }

    @objc func showMainWindow() {
        rememberCurrentExternalApplication()

        if let window = mainWindow {
            configureWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let history else { return }

        let rootView = ContentView()
            .environmentObject(history)
            .environmentObject(self)
        let hostingController = NSHostingController(rootView: rootView)
        let window = MenuBarWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "EchoCopy"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        configureWindow(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func pasteHistoryItem(_ item: ClipboardItem) {
        rememberCurrentExternalApplication()
        guard PasteboardWriter.write(item) else { return }
        mainWindow?.close()
        PasteExecutor.pastePreparedClipboard(into: lastExternalApplication)
    }

    func prepareForHistoryInteraction() {
        rememberCurrentExternalApplication()
    }

    private func rememberCurrentExternalApplication() {
        guard let currentApplication = NSWorkspace.shared.frontmostApplication,
              currentApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        lastExternalApplication = currentApplication
    }

    deinit {
        memoryReliefWorkItem?.cancel()
    }
}

// MARK: - UI Views

struct ContentView: View {
    @EnvironmentObject var history: ClipboardHistory
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var searchText = ""

    var filteredItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history.items }
        return history.items.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
    }

    var pinnedItems: [ClipboardItem] {
        filteredItems.filter(\.isPinned)
    }

    var unpinnedItems: [ClipboardItem] {
        filteredItems.filter { !$0.isPinned }
    }

    var body: some View {
        ZStack {
            // Use Material background for a native feel
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Compact Header
                VStack(spacing: 10) {
                    HStack(alignment: .center) {
                        Text("EchoCopy")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        
                        Spacer()
                        
                        SettingsButton {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                                .background(Color.primary.opacity(0.01))
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    // Compact Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.6))
                        
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                        
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary.opacity(0.4))
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .padding(.horizontal, 10)
                }
                .padding(.bottom, 10)

                if !appDelegate.accessibilityTrusted {
                    AccessibilityGuidanceBanner(appDelegate: appDelegate)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }

                if let persistenceError = history.persistenceError {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.trianglebadge.exclamationmark")
                                .foregroundColor(.orange)

                            Text(persistenceError)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }

                        if history.canRetryHistoryUnlock {
                            Button("Repair Secure History") {
                                history.retryHistoryUnlock()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }

                // Content
                if history.items.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                        }

                        VStack(spacing: 4) {
                            Text("Your history is empty")
                                .font(.system(size: 15, weight: .semibold))
                            
                            Text("Copied items will appear here.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("No matches found")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)

                        Button("Clear Search") {
                            searchText = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            if !pinnedItems.isEmpty {
                                SectionHeader(title: "Pinned")
                                    .padding(.horizontal, 12)
                                ForEach(pinnedItems) { item in
                                    ClipboardItemRow(
                                        item: item,
                                        history: history,
                                        onPaste: appDelegate.pasteHistoryItem
                                    )
                                }
                                .padding(.horizontal, 4)
                                
                                if !unpinnedItems.isEmpty {
                                    SectionHeader(title: "Recent")
                                        .padding(.horizontal, 12)
                                        .padding(.top, 8)
                                }
                            }

                            ForEach(unpinnedItems) { item in
                                ClipboardItemRow(
                                    item: item,
                                    history: history,
                                    onPaste: appDelegate.pasteHistoryItem
                                )
                            }
                            .padding(.horizontal, 4)
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Footer
                HStack {
                    Menu {
                        Button(role: .destructive) {
                            history.clearHistory()
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                        
                        Button {
                            history.clearUnpinnedHistory()
                        } label: {
                            Label("Clear Unpinned Only", systemImage: "pin.slash")
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Clear options")

                    Spacer()

                    Text("\(history.items.count) items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow).opacity(0.5))
                .borderTop()
            }
        }
        .frame(minWidth: 320, minHeight: 400)
    }
}

struct AccessibilityGuidanceBanner: View {
    @ObservedObject var appDelegate: AppDelegate
    @State private var showSetupSteps = true

    private var currentAppPath: String {
        Bundle.main.bundleURL.path
    }

    @ViewBuilder
    private func setupStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "(number).circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Finish Accessibility setup")
                        .font(.system(size: 12, weight: .semibold))

                    Text(
                        "This is a one-time setup for the current signed EchoCopy app. The old denied row cannot authorize this copy."
                    )
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Button(showSetupSteps ? "Hide setup steps" : "Show setup steps") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSetupSteps.toggle()
                }
            }
            .buttonStyle(.link)
            .controlSize(.small)

            if showSetupSteps {
                VStack(alignment: .leading, spacing: 7) {
                    setupStep(
                        1,
                        "Open Privacy & Security → Accessibility",
                        "Use the button below to open the correct pane."
                    )
                    setupStep(
                        2,
                        "Clear any old denied EchoCopy row",
                        "If the old row is still present, select it and click −. If you already deleted it, continue to the next step."
                    )
                    setupStep(
                        3,
                        "Add this current app",
                        "Click +. If EchoCopy is not listed, press ⌘⇧G in the picker and use the path shown below."
                    )
                    Text(currentAppPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 20)
                    setupStep(
                        4,
                        "Turn EchoCopy on",
                        "Select the newly added row, enable its switch, then return here. EchoCopy will refresh automatically."
                    )

                    HStack(spacing: 8) {
                        Button("Open Accessibility Settings") {
                            _ = appDelegate.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Show EchoCopy in Finder") {
                            appDelegate.revealCurrentAppInFinder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 2)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Visual Effect View
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
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

enum PasteboardWriter {
    @MainActor
    @discardableResult
    static func write(
        _ item: ClipboardItem,
        to pasteboard: NSPasteboard = .general,
        writeTracker: PasteboardWriteTracker = .shared
    ) -> Bool {
        let didWrite: Bool

        switch item.contentType {
        case .url where URL(string: item.content)?.isFileURL == true:
            // Older versions stored Finder file URLs as ordinary links.
            guard let url = URL(string: item.content) else { return false }
            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects([url as NSURL])
        case .text, .url:
            pasteboard.clearContents()
            didWrite = pasteboard.setString(item.content, forType: .string)
            if let rtfBase64 = item.rtfContent,
               let rtfData = Data(base64Encoded: rtfBase64) {
                pasteboard.setData(rtfData, forType: .rtf)
            }
        case .image:
            guard let data = Data(base64Encoded: item.content),
                  let pasteboardType = imagePasteboardType(for: data) else {
                return false
            }

            pasteboard.clearContents()
            didWrite = pasteboard.setData(data, forType: pasteboardType)
        case .file:
            let url = URL(string: item.content).flatMap { $0.isFileURL ? $0 : nil }
                ?? URL(fileURLWithPath: item.content)
            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects([url as NSURL])
        }

        if didWrite {
            writeTracker.recordInternalWrite(changeCount: pasteboard.changeCount)
        }

        return didWrite
    }

    private static func imagePasteboardType(for data: Data) -> NSPasteboard.PasteboardType? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(imageSource) else {
            return nil
        }

        return NSPasteboard.PasteboardType(typeIdentifier as String)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

struct ClipboardImagePreview: View {
    let itemID: UUID
    let base64Content: String
    var height: CGFloat = 72

    @State private var thumbnail: CGImage?
    @State private var hasRequestedThumbnail = false

    var body: some View {
        ZStack {
            Color.primary.opacity(0.03)

            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityLabel("Clipboard image preview")
        .onAppear {
            guard !hasRequestedThumbnail else { return }
            hasRequestedThumbnail = true

            ClipboardThumbnailCache.shared.load(
                itemID: itemID,
                base64Content: base64Content
            ) { image in
                thumbnail = image
            }
        }
        .onDisappear {
            // Visible rows may retain their SwiftUI state after leaving a lazy
            // stack. Release that reference and let the bounded cache own it.
            thumbnail = nil
            hasRequestedThumbnail = false
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let history: ClipboardHistory
    let onPaste: (ClipboardItem) -> Void
    @State private var isHovered = false

    var contentIcon: String {
        switch item.contentType {
        case .text: return "doc.text"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        }
    }

    var iconColor: Color {
        switch item.contentType {
        case .text: return .blue
        case .image: return .purple
        case .url: return .orange
        case .file: return .green
        }
    }

    var contentPreview: String {
        item.listPreview
    }

    var contentTypeLabel: String {
        switch item.contentType {
        case .text: return "Text"
        case .image: return "Image"
        case .url: return "Link"
        case .file: return "File"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.contentType == .image {
                HStack(spacing: 10) {
                    ClipboardImagePreview(
                        itemID: item.id,
                        base64Content: item.content,
                        height: 72
                    )
                    .frame(width: 112)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.filename ?? "Screenshot")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text("Image · \(item.timestamp.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        if item.isPinned {
                            Label("Pinned", systemImage: "pin.fill")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer(minLength: 4)

                    if isHovered || item.isPinned {
                        Button(action: { history.togglePin(for: item) }) {
                            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(item.isPinned ? .orange : .secondary)
                                .frame(width: 26, height: 26)
                                .background(
                                    item.isPinned
                                        ? Color.orange.opacity(0.1)
                                        : Color.primary.opacity(0.05)
                                )
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(item.isPinned ? "Unpin" : "Pin")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            } else {
                // Compact Text/URL/File Layout
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(iconColor.opacity(0.1))
                        
                        Image(systemName: contentIcon)
                            .foregroundColor(iconColor)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(contentPreview)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        HStack(spacing: 6) {
                            Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.6))

                            if item.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    if isHovered || item.isPinned {
                        Button(action: { history.togglePin(for: item) }) {
                            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(item.isPinned ? .orange : .secondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    item.isPinned
                                        ? Color.orange.opacity(0.1)
                                        : Color.primary.opacity(0.05)
                                )
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(item.isPinned ? "Unpin" : "Pin")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            pasteItem()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contentTypeLabel): \(contentPreview)")
        .accessibilityHint("Pastes this item into the previous app")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            pasteItem()
        }
        .contextMenu {
            Button {
                pasteItem()
            } label: {
                Label("Paste into Previous App", systemImage: "doc.on.clipboard")
            }

            Button {
                PasteboardWriter.write(item)
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }

            Button {
                history.togglePin(for: item)
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }

            Divider()

            Button(role: .destructive) {
                history.removeItem(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func pasteItem() {
        onPaste(item)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var history: ClipboardHistory
    @EnvironmentObject var appDelegate: AppDelegate
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage(ScreenshotCaptureCoordinator.automaticClipboardPreferenceKey)
    private var automaticallyCopyScreenshots = false
    @State private var selectedTab = 0

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var excludedAppNames: [String] {
        Array(Set(history.excludedApps.map(appName(from:)))).sorted()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // General Tab
            VStack(alignment: .leading, spacing: 16) {
                Text("General")
                    .font(.system(size: 20, weight: .bold))

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if !appDelegate.accessibilityTrusted {
                            AccessibilityGuidanceBanner(appDelegate: appDelegate)
                        }

                        Toggle(
                            "Add standard screenshots to EchoCopy",
                            isOn: $automaticallyCopyScreenshots
                        )

                        Text(
                            "Standard Shift-Command-3 and Shift-Command-4 "
                            + "captures remain saved in your "
                            + "Screenshot location and are also added to the clipboard."
                        )
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Text("Off by default. Uses EchoCopy's existing Accessibility access; no Desktop-folder access is requested.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(0)

            // Updates Tab
            VStack(alignment: .leading, spacing: 16) {
                Text("Updates")
                    .font(.system(size: 20, weight: .bold))

                // Current version info
                HStack {
                    Text("Current Version:")
                        .foregroundColor(.secondary)
                    Text(currentVersion)
                        .fontWeight(.medium)
                }

                // Update status
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        if updateChecker.isChecking {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Checking for updates...")
                                    .foregroundColor(.secondary)
                            }
                        } else if let error = updateChecker.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .foregroundColor(.secondary)
                            }
                        } else if updateChecker.updateAvailable, let latestVersion = updateChecker.latestVersion {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 20))
                                    VStack(alignment: .leading) {
                                        Text("Update Available!")
                                            .fontWeight(.semibold)
                                        Text("Version \(latestVersion) is available")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Button {
                                    updateChecker.openReleasePage()
                                } label: {
                                    Text("Open Official Release Page")
                                }
                                .buttonStyle(.borderedProminent)

                                Text("Download and install updates manually from the official release page.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else if updateChecker.latestVersion != nil {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("You're up to date!")
                            }
                        } else {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text("Click below to check for updates")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        HStack {
                            Button("Check for Updates") {
                                updateChecker.checkForUpdates()
                            }
                            .disabled(updateChecker.isChecking)

                            Spacer()

                            if let lastCheck = updateChecker.lastCheckDate {
                                Text("Last checked: \(lastCheck.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(20)
            .tabItem {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .tag(1)

            // App Exclusions Tab
            VStack(alignment: .leading, spacing: 16) {
                Text("App Exclusions")
                    .font(.system(size: 20, weight: .bold))

            Text("Clipboard content from these apps will not be saved to history")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // List of excluded apps
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(excludedAppNames, id: \.self) { name in
                        HStack {
                            Image(systemName: "shield.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 12))

                            Text(name)
                                .font(.system(size: 13))

                            Spacer()

                            Button(action: {
                                let matchingBundleIDs = history.excludedApps.filter {
                                    appName(from: $0) == name
                                }
                                for bundleID in matchingBundleIDs {
                                    history.removeExcludedApp(bundleID)
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from exclusion list")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(8)
            }
            .frame(height: 200)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            // Add new app
            VStack(alignment: .leading, spacing: 8) {
                Text("Add App to Exclude")
                    .font(.system(size: 14, weight: .semibold))

                HStack {
                    Button("Choose Application…") {
                        chooseApplicationToExclude()
                    }

                    if let currentApp = NSWorkspace.shared.frontmostApplication,
                       let bundleID = currentApp.bundleIdentifier,
                       bundleID != Bundle.main.bundleIdentifier,
                       !history.excludedApps.contains(bundleID) {
                        Button("Exclude \(currentApp.localizedName ?? "Current App")") {
                            history.addExcludedApp(bundleID)
                        }
                    }
                }

                Text("Choose an installed app—no bundle ID lookup required.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()
            }
            .padding(20)
            .tabItem {
                Label("Exclusions", systemImage: "shield")
            }
            .tag(2)
        }
        .frame(width: 560, height: 520)
    }

    private func chooseApplicationToExclude() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to exclude"
        panel.prompt = "Exclude App"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let appURL = panel.url,
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
            return
        }
        history.addExcludedApp(bundleID)
    }

    private func appName(from bundleID: String) -> String {
        // Try to get friendly name for known apps
        let knownApps: [String: String] = [
            "com.1password.1password": "1Password",
            "com.agilebits.onepassword7": "1Password 7",
            "com.lastpass.LastPass": "LastPass",
            "com.bitwarden.desktop": "Bitwarden",
            "com.dashlane.Dashlane": "Dashlane",
            "com.keeper.KeeperPasswordManager": "Keeper",
            "com.nordpass.NordPass": "NordPass",
            "com.apple.keychainaccess": "Keychain Access",
            "com.apple.Passwords": "Passwords",
            "com.apple.passwords": "Passwords"
        ]

        return knownApps[bundleID] ?? bundleID
    }
}

// MARK: - Update Checker

class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var isChecking = false
    @Published var lastCheckDate: Date?
    @Published var errorMessage: String?

    // GitHub repo
    private let githubOwner = "conman777"
    private let githubRepo = "EchoCopy"
    private let releasePageURL = URL(string: "https://github.com/conman777/EchoCopy/releases/latest")!

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkForUpdates() {
        guard !isChecking else { return }

        isChecking = true
        errorMessage = nil

        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.isChecking = false
                self.errorMessage = "Invalid URL"
            }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("EchoCopy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                self.lastCheckDate = Date()

                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 404 {
                        self.errorMessage = "No releases found"
                        self.updateAvailable = false
                        return
                    }

                    if !(200...299).contains(httpResponse.statusCode) {
                        self.errorMessage = "Update check failed (HTTP \(httpResponse.statusCode))"
                        return
                    }
                }

                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tagName = json["tag_name"] as? String {

                        let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                        self.latestVersion = latestVersion

                        self.updateAvailable = UpdateVersionPolicy.updateAvailable(
                            latest: latestVersion,
                            current: self.currentVersion
                        )
                        self.errorMessage = nil
                    } else {
                        self.errorMessage = "Could not parse release info"
                    }
                } catch {
                    self.errorMessage = "Parse error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(releasePageURL)
    }
}

// MARK: - App

@main
struct EchoCopyApp: App {
    @StateObject private var history: ClipboardHistory
    private let clipboardMonitor: ClipboardMonitor
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(history)
                .environmentObject(appDelegate)
        }
    }

    init() {
        let historyInstance = ClipboardHistory()
        _history = StateObject(wrappedValue: historyInstance)

        let monitor = ClipboardMonitor(history: historyInstance)
        clipboardMonitor = monitor

        // Set up app delegate references before starting monitor
        appDelegate.history = historyInstance

        // Start monitoring clipboard changes
        monitor.start()
    }
}
