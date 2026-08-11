import SwiftUI
import AppKit
import Foundation
import Combine
import Observation
import ApplicationServices
import Carbon.HIToolbox
import ImageIO
import OSLog

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
            let firstLine = content.components(separatedBy: .newlines).first ?? ""
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func removeItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
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
        guard !persistenceBlocked else {
            canRetryHistoryUnlock = true
            persistenceError = keychainRepairMessage
            return
        }

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

        persistenceBlocked = false
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
            let itemCountBeforeBudget = sanitizedItems.count
            items = sanitizedItems
            enforceItemCountLimit()
            if items.count != decoded.count || items.count != itemCountBeforeBudget {
                scheduleHistorySave()
            }
            persistenceBlocked = false
            canRetryHistoryUnlock = false
            persistenceError = nil
        } catch {
            if !preserveItemsOnFailure {
                items = []
            }
            let requiresUnlock = (error as? EncryptedHistoryStoreError)?.requiresKeychainUnlock ?? false
            if requiresUnlock {
                historyStore.recordKeychainRepairRequired()
            }
            persistenceBlocked = requiresUnlock
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

class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastObservedFrontmostBundleID: String?
    private let history: ClipboardHistory
    private let writeTracker: PasteboardWriteTracker
    private let screenshotCoordinator: ScreenshotCaptureCoordinator
    private let processingQueue = DispatchQueue(
        label: "com.yourcompany.echocopy.clipboard-processing",
        qos: .userInitiated
    )
    private let checkInterval: TimeInterval = 0.5

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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: self.checkInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkClipboard()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        let currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let previouslyObservedBundleID = lastObservedFrontmostBundleID
        lastObservedFrontmostBundleID = currentBundleID

        guard currentChangeCount != lastChangeCount else { return }
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
            history.addItem(url.absoluteString ?? "", contentType: .url)
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
}

// MARK: - System Monitor

class SystemMonitor {
    private var updateTimer: Timer?
    private var cpuInfo: processor_info_array_t?
    private var prevCpuInfo: processor_info_array_t?
    private var numCpuInfo: mach_msg_type_number_t = 0
    private var numPrevCpuInfo: mach_msg_type_number_t = 0
    private var numCPUs: uint = 0
    private let cpuUsageLock = NSLock()
    private let statsQueue = DispatchQueue(
        label: "com.yourcompany.echocopy.system-stats",
        qos: .utility
    )

    var onUpdate: ((String) -> Void)?

    init() {
        let mibKeys: [Int32] = [CTL_HW, HW_NCPU]
        var numCPUsU: uint = 0
        var sizeOfNumCPUs = MemoryLayout<uint>.size
        let status = mibKeys.withUnsafeBufferPointer { mib in
            sysctl(UnsafeMutablePointer(mutating: mib.baseAddress), 2, &numCPUsU, &sizeOfNumCPUs, nil, 0)
        }
        if status == 0 {
            numCPUs = numCPUsU
        }
    }

    func start() {
        // Update immediately
        requestStatsUpdate()

        // The tooltip does not need high-frequency refreshes. Keep periodic
        // system calls off the main thread and reduce unnecessary wakeups.
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.requestStatsUpdate()
        }
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func requestStatsUpdate() {
        statsQueue.async { [weak self] in
            guard let self else { return }

            let cpuUsage = self.getCPUUsage()
            let memoryUsage = self.getMemoryUsage()
            let diskUsage = self.getDiskUsage()

            let tooltip = """
            CPU: \(String(format: "%.1f", cpuUsage))%
            Memory: \(memoryUsage.used) / \(memoryUsage.total) (\(String(format: "%.0f", memoryUsage.percentage))%)
            Disk: \(diskUsage.used) / \(diskUsage.total) (\(String(format: "%.0f", diskUsage.percentage))%)
            """

            DispatchQueue.main.async { [weak self] in
                self?.onUpdate?(tooltip)
            }
        }
    }

    private func getCPUUsage() -> Double {
        var numCPUsU: natural_t = 0
        var cpuInfoLocal: processor_info_array_t?
        var numCpuInfoLocal: mach_msg_type_number_t = 0

        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfoLocal, &numCpuInfoLocal)

        guard err == KERN_SUCCESS, let cpuInfoLocal = cpuInfoLocal else {
            return 0.0
        }

        cpuUsageLock.lock()
        defer { cpuUsageLock.unlock() }

        var totalUsage: Double = 0

        if let prevCpuInfo = prevCpuInfo {
            for i in 0..<Int(numCPUs) {
                var inUse: Int32
                var total: Int32

                let offset = Int32(CPU_STATE_MAX) * Int32(i)

                inUse = cpuInfoLocal[Int(offset + CPU_STATE_USER)]
                    - prevCpuInfo[Int(offset + CPU_STATE_USER)]
                    + cpuInfoLocal[Int(offset + CPU_STATE_SYSTEM)]
                    - prevCpuInfo[Int(offset + CPU_STATE_SYSTEM)]
                    + cpuInfoLocal[Int(offset + CPU_STATE_NICE)]
                    - prevCpuInfo[Int(offset + CPU_STATE_NICE)]

                total = inUse
                    + cpuInfoLocal[Int(offset + CPU_STATE_IDLE)]
                    - prevCpuInfo[Int(offset + CPU_STATE_IDLE)]

                if total > 0 {
                    totalUsage += Double(inUse) / Double(total) * 100.0
                }
            }

            // Deallocate previous
            let prevSize = vm_size_t(MemoryLayout<integer_t>.stride * Int(numPrevCpuInfo))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevCpuInfo), prevSize)
        }

        prevCpuInfo = cpuInfoLocal
        numPrevCpuInfo = numCpuInfoLocal
        cpuInfo = cpuInfoLocal
        numCpuInfo = numCpuInfoLocal

        return numCPUs > 0 ? totalUsage / Double(numCPUs) : 0.0
    }

    private func getMemoryUsage() -> (used: String, total: String, percentage: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return ("--", "--", 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let totalMemory = ProcessInfo.processInfo.physicalMemory

        let activeMemory = UInt64(stats.active_count) * pageSize
        let wiredMemory = UInt64(stats.wire_count) * pageSize
        let compressedMemory = UInt64(stats.compressor_page_count) * pageSize

        let usedMemory = activeMemory + wiredMemory + compressedMemory
        let percentage = Double(usedMemory) / Double(totalMemory) * 100.0

        return (formatBytes(usedMemory), formatBytes(totalMemory), percentage)
    }

    private func getDiskUsage() -> (used: String, total: String, percentage: Double) {
        let fileManager = FileManager.default

        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: "/")

            if let totalSpace = attributes[.systemSize] as? UInt64,
               let freeSpace = attributes[.systemFreeSize] as? UInt64 {
                let usedSpace = totalSpace - freeSpace
                let percentage = Double(usedSpace) / Double(totalSpace) * 100.0
                return (formatBytes(usedSpace), formatBytes(totalSpace), percentage)
            }
        } catch {
            // Ignore error
        }

        return ("--", "--", 0)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824 // 1024^3
        if gb >= 100 {
            return String(format: "%.0f GB", gb)
        } else if gb >= 10 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.2f GB", gb)
        }
    }

    deinit {
        stop()

        // Clean up CPU info
        if let cpuInfo = cpuInfo {
            let size = vm_size_t(MemoryLayout<integer_t>.stride * Int(numCpuInfo))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }
    }
}

// MARK: - Popup Window Manager

class PopupWindowManager {
    private var popupWindow: NSWindow?
    private weak var history: ClipboardHistory?
    private var clickOutsideMonitor: Any?
    private var windowWillCloseObserver: NSObjectProtocol?

    init(history: ClipboardHistory) {
        self.history = history
    }

    deinit {
        closePopup()
    }

    func showPopup() {
        guard let history = history else { return }

        // Close existing popup if open (and clean up monitors/observers)
        closePopup()

        // Create hosting controller with popup view
        let popupView = PopupView(history: history, onDismiss: { [weak self] in
            self?.closePopup()
        })
        .environmentObject(history)

        let hostingController = NSHostingController(rootView: popupView)
        let popupSize = NSSize(width: 240, height: 190)
        hostingController.view.frame = NSRect(origin: .zero, size: popupSize)

        // Position near mouse cursor (clamped to the current screen's visible frame)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: mouseLocation.x, y: mouseLocation.y, width: popupSize.width, height: popupSize.height)

        var origin = CGPoint(
            x: mouseLocation.x - (popupSize.width / 2),
            y: mouseLocation.y - popupSize.height - 12
        )

        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - popupSize.width - 8)
        origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - popupSize.height - 8)

        let frame = NSRect(origin: origin, size: popupSize)

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

        // Observe window close to ensure cleanup
        windowWillCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.closePopup()
        }

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

    func closePopup() {
        // Remove click monitor
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }

        // Remove window observer
        if let observer = windowWillCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            windowWillCloseObserver = nil
        }

        let windowToClose = popupWindow
        popupWindow = nil
        windowToClose?.close()
    }
}

// MARK: - Popup View

struct PopupView: View {
    @ObservedObject var history: ClipboardHistory
    let onDismiss: () -> Void
    @State private var hoveredItemId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if history.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Empty")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 1) {
                            ForEach(Array(history.items.prefix(15).enumerated()), id: \.element.id) { index, item in
                                PopupItemRow(
                                    item: item,
                                    index: index,
                                    isHovered: hoveredItemId == item.id,
                                    onHover: { hovered in
                                        hoveredItemId = hovered ? item.id : nil
                                    },
                                    onSelect: {
                                        copyItem(item)
                                        onDismiss()
                                    }
                                )
                            }
                        }
                        .padding(4)
                    }
                }
            }
        }
        .frame(width: 260, height: 360)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func copyItem(_ item: ClipboardItem) {
        PasteboardWriter.write(item)
    }
}

struct PopupItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onSelect: () -> Void

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
        switch item.contentType {
        case .text:
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = content.components(separatedBy: .newlines)
            let firstLine = lines.first ?? ""
            return firstLine.count > 40 ? String(firstLine.prefix(40)) + "..." : firstLine
        case .image: return item.filename ?? "Image"
        case .url: return item.content
        case .file: return item.filename ?? "File"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .secondary.opacity(0.4))
                .frame(width: 12)

            Image(systemName: contentIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isHovered ? .white : iconColor)
                .frame(width: 14)

            Text(contentPreview)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(isHovered ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isHovered {
                Image(systemName: "return")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.blue : Color.clear)
        )
        .onHover { hovering in
            onHover(hovering)
        }
        .onTapGesture {
            onSelect()
        }
        .contentShape(Rectangle())
    }
}


// MARK: - Menu Bar Manager

@MainActor
class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private weak var history: ClipboardHistory?
    private weak var appDelegate: AppDelegate?
    private var historySubscription: AnyCancellable?
    private var systemMonitor: SystemMonitor?

    init(history: ClipboardHistory, appDelegate: AppDelegate) {
        self.history = history
        self.appDelegate = appDelegate
        super.init()
        setupMenuBar()
        setupHistoryObserver()
        setupSystemMonitor()
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
        }

        updateMenu()
    }

    private func setupHistoryObserver() {
        // Subscribe to changes in the history
        historySubscription = history?.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
    }

    private func setupSystemMonitor() {
        systemMonitor = SystemMonitor()
        systemMonitor?.onUpdate = { [weak self] tooltip in
            self?.statusItem?.button?.toolTip = tooltip
        }
        systemMonitor?.start()
    }

    private func updateMenu() {
        let menu = NSMenu()

        guard let history else { return }

        // Show top 10 items
        let pinned = history.items.filter { $0.isPinned }
        let unpinned = history.items.filter { !$0.isPinned }
        let topItems = Array((pinned + unpinned).prefix(10))
        for (index, item) in topItems.enumerated() {
            var preview = item.menuPreview
            preview = preview.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            preview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            if preview.isEmpty { preview = "Item" }

            let clipped = preview.count > 40
                ? String(preview.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                : preview

            let title = "\(index + 1). \(clipped)"
            let menuItem = NSMenuItem(title: title, action: #selector(MenuBarManager.pasteItem(_:)), keyEquivalent: "")
            menuItem.representedObject = item
            menuItem.target = self
            menu.addItem(menuItem)
        }

        if !topItems.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        let openItem = NSMenuItem(title: "Open EchoCopy", action: #selector(MenuBarManager.openWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(MenuBarManager.openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Keep the menu attached so both left-click and control/right-click
        // open it using the standard macOS status-item behavior.
        statusItem?.menu = menu
    }

    @objc private func openWindow() {
        appDelegate?.showMainWindow()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func pasteItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardItem else { return }
        PasteboardWriter.write(item)
    }
}

// MARK: - Global Keyboard Shortcut Handler

class GlobalShortcutHandler {
    private static let logger = Logger(
        subsystem: "com.yourcompany.echocopy",
        category: "GlobalShortcutHandler"
    )

    private var eventMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var swallowedScreenshotKeyCodes = Set<CGKeyCode>()
    private var eventTapRetryScheduled = false
    private var lastLoggedAccessibilityTrust: Bool?
    private let screenshotCoordinator: ScreenshotCaptureCoordinator
    weak var history: ClipboardHistory?
    weak var appDelegate: AppDelegate?

    init(
        history: ClipboardHistory,
        appDelegate: AppDelegate,
        screenshotCoordinator: ScreenshotCaptureCoordinator = .shared
    ) {
        self.history = history
        self.appDelegate = appDelegate
        self.screenshotCoordinator = screenshotCoordinator
        setupGlobalShortcuts()
    }

    private func setupGlobalShortcuts() {
        checkAccessibilityAndInstall()
    }

    private func checkAccessibilityAndInstall() {
        // Isolated UI smoke tests do not need global shortcuts and must not
        // trigger a system Accessibility permission prompt.
        if ProcessInfo.processInfo.environment["ECHOCOPY_DISABLE_GLOBAL_SHORTCUTS"] == "1" {
            return
        }

        let trusted = AXIsProcessTrusted()
        appDelegate?.updateAccessibilityStatus(trusted)
        if lastLoggedAccessibilityTrust != trusted {
            lastLoggedAccessibilityTrust = trusted
            Self.logger.notice(
                "Accessibility trust reported by EchoCopy: \(trusted, privacy: .public)"
            )
        }

        if !trusted {
            // Poll silently because macOS provides no change notification.
            // Permission is user-managed in System Settings; EchoCopy never
            // reopens the Accessibility authorization prompt on its own.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.checkAccessibilityAndInstall()
            }
        } else {
            installEventTap()
        }
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
            // Keep non-swallowing shortcuts available, but do not permanently
            // give up on the active event tap after one transient failure.
            if eventMonitor == nil {
                eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handleFallbackGlobalKeyEvent(event)
                }
            }
            scheduleEventTapRetry()
            return
        }

        Self.logger.notice(
            "Active keyboard event tap installed at \(installedTapName ?? "unknown", privacy: .public)"
        )

        eventTapRetryScheduled = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func scheduleEventTapRetry() {
        guard !eventTapRetryScheduled else { return }
        eventTapRetryScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.eventTapRetryScheduled = false
            self.installEventTap()
        }
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

        let optionPressed = flags.contains(.maskAlternate)
        let cmdPressed = flags.contains(.maskCommand)
        let shiftPressed = flags.contains(.maskShift)
        let ctrlPressed = flags.contains(.maskControl)

        if keyCode == CGKeyCode(kVK_Escape) {
            screenshotCoordinator.cancelPendingCapture()
        }

        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isAutoRepeat,
           ScreenshotShortcutPolicy.isStandardScreenshotShortcut(
               keyCode: keyCode,
               flags: flags
           ),
           screenshotCoordinator.beginAutomaticClipboardCapture(
               startingPasteboardChangeCount: NSPasteboard.general.changeCount
           ) {
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

        // Control+V OR Cmd+Shift+V => show popup
        let cmdShiftVPressed = cmdPressed && shiftPressed && !optionPressed && !ctrlPressed && keyCode == CGKeyCode(kVK_ANSI_V)
        
        if (ctrlPressed && !optionPressed && !cmdPressed && !shiftPressed && keyCode == CGKeyCode(kVK_ANSI_V)) ||
           cmdShiftVPressed {
            Task { @MainActor [weak self] in
                self?.appDelegate?.showPopupWindow()
            }
            return nil
        }

        // Cmd+Option+1..9 => quick paste (we do NOT swallow, to preserve app shortcuts).
        if cmdPressed,
           optionPressed,
           !shiftPressed,
           !ctrlPressed,
           let digit = digitForKeyCode(keyCode),
           digit >= 1,
           digit <= 9 {
            Task { @MainActor [weak self] in
                self?.pasteQuickItem(at: digit - 1)
            }
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func digitForKeyCode(_ keyCode: CGKeyCode) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 1
        case kVK_ANSI_2: return 2
        case kVK_ANSI_3: return 3
        case kVK_ANSI_4: return 4
        case kVK_ANSI_5: return 5
        case kVK_ANSI_6: return 6
        case kVK_ANSI_7: return 7
        case kVK_ANSI_8: return 8
        case kVK_ANSI_9: return 9
        default: return nil
        }
    }

    private func handleFallbackGlobalKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let normalized = modifiers.subtracting([.capsLock, .numericPad, .function])
        let controlPressed = normalized == .control
        let cmdShiftPressed = normalized == [.command, .shift]
        let cmdAltPressed = normalized == [.command, .option]

        // Check for Control+V or Cmd+Shift+V to show popup
        if (controlPressed || cmdShiftPressed), event.charactersIgnoringModifiers == "v" {
            Task { @MainActor in
                self.appDelegate?.showPopupWindow()
            }
            return
        }

        // Only handle if Cmd+Option is pressed for quick paste
        guard cmdAltPressed else { return }

        // Numbers 1-9 for quick paste
        if let character = event.charactersIgnoringModifiers?.first,
           let digit = Int(String(character)), digit >= 1, digit <= 9 {
            Task { @MainActor in
                pasteQuickItem(at: digit - 1)
            }
        }
    }

    @MainActor
    private func pasteQuickItem(at index: Int) {
        guard let history = history else { return }
        guard index >= 0 && index < history.items.count else { return }

        let item = history.items[index]
        PasteboardWriter.write(item)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
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

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions options: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        return options
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            window.orderOut(nil)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var accessibilityTrusted = true
    var mainWindow: NSWindow?
    var menuBarManager: MenuBarManager?
    var shortcutHandler: GlobalShortcutHandler?
    var popupWindowManager: PopupWindowManager?
    var windowDelegate: MenuBarWindowDelegate?
    var localEventMonitor: Any?
    var globalClickMonitor: Any?
    var windowMiniaturizeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    weak var history: ClipboardHistory?
    weak var clipboardMonitor: ClipboardMonitor?
    private var hasAppliedPreferredSize = false

    func updateAccessibilityStatus(_ trusted: Bool) {
        if Thread.isMainThread {
            if accessibilityTrusted != trusted {
                accessibilityTrusted = trusted
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateAccessibilityStatus(trusted)
            }
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
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar and keyboard shortcuts
        // Ensure history is set before proceeding
        guard let history = history else {
            print("Warning: ClipboardHistory not initialized")
            return
        }

        menuBarManager = MenuBarManager(history: history, appDelegate: self)
        shortcutHandler = GlobalShortcutHandler(history: history, appDelegate: self)
        popupWindowManager = PopupWindowManager(history: history)

        // Setup window delegate for all windows - do this after a small delay to ensure windows are ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupWindowBehavior()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persist the latest coalesced snapshot before an orderly quit.
        history?.flushPersistence()
    }

    func applyWindowBehavior(to window: NSWindow) {
        configureWindow(window)
    }

    private func setupWindowBehavior() {
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

        // Add global monitor for clicks outside the window
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self, let window = self.mainWindow, window.isVisible else { return }
                
                let mouseLocation = NSEvent.mouseLocation
                if !window.frame.contains(mouseLocation) {
                    window.orderOut(nil)
                }
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
        let windowID = ObjectIdentifier(window)
        if windowMiniaturizeObservers[windowID] == nil {
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main) { [weak self] note in
                if let w = note.object as? NSWindow {
                    w.orderOut(nil)
                    self?.mainWindow = w
                }
            }
            windowMiniaturizeObservers[windowID] = observer
        }

        // Store reference
        self.mainWindow = window

        window.minSize = NSSize(width: 320, height: 400)

        if !hasAppliedPreferredSize {
            let preferredContentSize = NSSize(width: 350, height: 480)
            window.setContentSize(preferredContentSize)
            hasAppliedPreferredSize = true
        }
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
        if let window = mainWindow {
            configureWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Fallback: find the first non-panel window.
        if let window = NSApp.windows.first(where: { !$0.isKind(of: NSPanel.self) }) {
            configureWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.mainWindow = window
        }
    }

    @objc func showPopupWindow() {
        popupWindowManager?.showPopup()
    }

    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        
        // Use the standard action but ensure it has a target
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            // Fallback: try to find a window with "Settings" in title
            for window in NSApp.windows {
                if window.title.contains("Settings") || window.frameAutosaveName.contains("Settings") {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
            }
        }
    }

    deinit {
        // Clean up event monitors
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Clean up notification observers
        for (_, observer) in windowMiniaturizeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - UI Views

struct ContentView: View {
    @EnvironmentObject var history: ClipboardHistory
    @EnvironmentObject var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
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
                .background(WindowAccessor { window in
                    if let app = NSApp.delegate as? AppDelegate {
                        app.applyWindowBehavior(to: window)
                    }
                })

            VStack(spacing: 0) {
                // Compact Header
                VStack(spacing: 10) {
                    HStack(alignment: .center) {
                        Text("EchoCopy")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        
                        Spacer()
                        
                        Button {
                            openWindow(id: "settings")
                        } label: {
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

                        Text("Press ⌃V or ⇧⌘V to open quick paste")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                            .foregroundColor(.secondary)
                        
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
                                    ClipboardItemRow(item: item, history: history)
                                }
                                .padding(.horizontal, 4)
                                
                                if !unpinnedItems.isEmpty {
                                    SectionHeader(title: "Recent")
                                        .padding(.horizontal, 12)
                                        .padding(.top, 8)
                                }
                            }

                            ForEach(unpinnedItems) { item in
                                ClipboardItemRow(item: item, history: history)
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
            pasteboard.clearContents()
            didWrite = pasteboard.setString(item.content, forType: .string)
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

struct ClipboardImagePreview: View {
    let itemID: UUID
    let base64Content: String

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
        .frame(height: 140)
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
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let history: ClipboardHistory
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
        switch item.contentType {
        case .text:
            return item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: return item.filename ?? "Image"
        case .url: return item.content
        case .file: return item.filename ?? "[File]"
        }
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
                // Large Image Layout
                VStack(alignment: .leading, spacing: 8) {
                    ClipboardImagePreview(
                        itemID: item.id,
                        base64Content: item.content
                    )
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.filename ?? "Screenshot")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
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
                        
                        Spacer()
                        
                        // Action buttons for image
                        if isHovered || item.isPinned {
                            HStack(spacing: 4) {
                                Button(action: { pasteItem() }) {
                                    Image(systemName: "doc.on.doc.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.blue)
                                        .frame(width: 26, height: 26)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .opacity(isHovered ? 1 : 0)

                                Button(action: { history.togglePin(for: item) }) {
                                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(item.isPinned ? .orange : .secondary)
                                        .frame(width: 26, height: 26)
                                        .background(item.isPinned ? Color.orange.opacity(0.1) : Color.primary.opacity(0.05))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(10)
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
                        HStack(spacing: 2) {
                            Button(action: { pasteItem() }) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.blue)
                                    .frame(width: 22, height: 22)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .opacity(isHovered ? 1 : 0)

                            Button(action: { history.togglePin(for: item) }) {
                                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(item.isPinned ? .orange : .secondary)
                                    .frame(width: 22, height: 22)
                                    .background(item.isPinned ? Color.orange.opacity(0.1) : Color.primary.opacity(0.05))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.opacity)
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
        .contextMenu {
            Button {
                pasteItem()
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
        PasteboardWriter.write(item)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var history: ClipboardHistory
    @EnvironmentObject var appDelegate: AppDelegate
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage(ScreenshotCaptureCoordinator.automaticClipboardPreferenceKey)
    private var automaticallyCopyScreenshots = true
    @State private var newAppBundleID = ""
    @State private var showInvalidWarning = false
    @State private var selectedTab = 0

    private var trimmedBundleID: String {
        newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValidBundleID: Bool {
        return !trimmedBundleID.isEmpty &&
               trimmedBundleID.contains(".") &&
               trimmedBundleID != Bundle.main.bundleIdentifier
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.4"
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
                            "Automatically copy screenshots to the clipboard",
                            isOn: $automaticallyCopyScreenshots
                        )

                        Text(
                            "Standard Shift-Command-3, Shift-Command-4, and "
                            + "Shift-Command-6 captures remain saved in your "
                            + "Screenshot location and are also added to the clipboard."
                        )
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Text("Uses EchoCopy's existing Accessibility access; no Desktop-folder access is requested.")
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
                    ForEach(Array(history.excludedApps).sorted(), id: \.self) { bundleID in
                        HStack {
                            Image(systemName: "shield.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 12))

                            Text(appName(from: bundleID))
                                .font(.system(size: 13))

                            Spacer()

                            Button(action: {
                                history.removeExcludedApp(bundleID)
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
                    TextField("Bundle ID (e.g., com.apple.Safari)", text: $newAppBundleID)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        if isValidBundleID {
                            history.addExcludedApp(trimmedBundleID)
                            newAppBundleID = ""
                            showInvalidWarning = false
                        } else {
                            showInvalidWarning = true
                        }
                    }
                    .disabled(trimmedBundleID.isEmpty)
                }

                if showInvalidWarning && !isValidBundleID && !trimmedBundleID.isEmpty {
                    Text("Invalid bundle ID format. Must contain '.' (e.g., com.company.app)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }

                Text("Tip: Copy from the currently active app")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let currentApp = NSWorkspace.shared.frontmostApplication,
                   let bundleID = currentApp.bundleIdentifier,
                   bundleID != Bundle.main.bundleIdentifier,
                   !history.excludedApps.contains(bundleID) {
                    Button("Add Current App: \(currentApp.localizedName ?? bundleID)") {
                        history.addExcludedApp(bundleID)
                    }
                    .font(.system(size: 12))
                } else if let currentApp = NSWorkspace.shared.frontmostApplication,
                          currentApp.bundleIdentifier == Bundle.main.bundleIdentifier {
                    Text("Cannot exclude EchoCopy itself")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }

            Spacer()
            }
            .padding(20)
            .tabItem {
                Label("Exclusions", systemImage: "shield")
            }
            .tag(2)
        }
        .frame(width: 500, height: 450)
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.4"
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

                        self.updateAvailable = self.isNewerVersion(latestVersion, than: self.currentVersion)
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

    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(newParts.count, currentParts.count) {
            let newPart = i < newParts.count ? newParts[i] : 0
            let currentPart = i < currentParts.count ? currentParts[i] : 0

            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        return false
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
        WindowGroup {
            ContentView()
                .environmentObject(history)
                .environmentObject(appDelegate)
        }
        .windowStyle(.hiddenTitleBar)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(history)
                .environmentObject(appDelegate)
        }

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
        appDelegate.clipboardMonitor = monitor

        // Start monitoring clipboard changes
        monitor.start()
    }
}
