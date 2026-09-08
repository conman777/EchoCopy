import AppKit
import AVFoundation
import Foundation
import Darwin

/// Watches only the configured Screenshot destination, never imports existing
/// captures. Videos remain file references; screenshot bytes are handled by the caller.
@MainActor
final class ScreenCaptureFileMonitor: ObservableObject {
    static let preferenceKey = "AutomaticallyCopyScreenRecordings"
    @Published private(set) var status = ""
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var directoryEvents: DispatchSourceFileSystemObject?
    private var quickScan: DispatchWorkItem?
    private var quickChecksRemaining = 0
    private var rescanRequested = false
    private var directory: URL?
    private var tracker = ScreenRecordingTracker()
    private var scanning = false
    private var generation = 0
    private let defaults: UserDefaults
    private let destination: () -> URL
    private let onRecording: (URL) async -> Bool
    private let screenshots: Bool
    private var enabledKey: String { screenshots ? ScreenshotCaptureCoordinator.automaticClipboardPreferenceKey : Self.preferenceKey }

    init(defaults: UserDefaults = .standard, screenshots: Bool = false,
         destination: @escaping () -> URL = ScreenshotCaptureCoordinator.systemScreenshotDirectory,
         onRecording: @escaping (URL) async -> Bool) {
        self.defaults = defaults
        self.screenshots = screenshots
        self.destination = destination
        self.onRecording = onRecording
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancelDirectoryWatch()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        generation += 1
        directory = nil
        tracker = ScreenRecordingTracker()
    }

    private func refresh() {
        guard defaults.bool(forKey: enabledKey) else {
            timer?.invalidate()
            timer = nil
            cancelDirectoryWatch()
            generation += 1
            directory = nil
            tracker = ScreenRecordingTracker()
            status = ""
            return
        }
        if timer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.scan() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            scan()
        }
    }

    private func cancelDirectoryWatch() {
        directoryEvents?.cancel()
        directoryEvents = nil
        quickScan?.cancel()
        quickScan = nil
        quickChecksRemaining = 0
        rescanRequested = false
    }

    private func watchDirectory(_ url: URL) {
        guard directoryEvents == nil else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return } // The timer remains a fallback.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self, weak source] in
            Task { @MainActor in
                guard let self else { return }
                if let flags = source?.data, !flags.intersection([.rename, .delete]).isEmpty {
                    self.cancelDirectoryWatch()
                }
                self.quickChecksRemaining = 8
                self.scan()
            }
        }
        directoryEvents = source
        source.resume()
    }

    private func scheduleQuickScan() {
        guard quickScan == nil, defaults.bool(forKey: enabledKey) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.quickScan = nil
            self.scan()
        }
        quickScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func scan() {
        guard defaults.bool(forKey: enabledKey) else { return }
        guard !scanning else {
            rescanRequested = true
            return
        }
        let currentDirectory = destination().standardizedFileURL
        if directory != currentDirectory {
            cancelDirectoryWatch()
            directory = currentDirectory
            tracker = ScreenRecordingTracker()
            generation += 1
        }
        watchDirectory(currentDirectory)
        let currentGeneration = generation
        let screenshots = self.screenshots
        scanning = true
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try ScreenRecordingCandidate.scan(directory: currentDirectory, screenshots: screenshots) }
            }.value
            defer {
                scanning = false
                if currentGeneration == generation {
                    if rescanRequested {
                        rescanRequested = false
                        scheduleQuickScan()
                    } else if screenshots && tracker.hasPending && quickChecksRemaining > 0 {
                        quickChecksRemaining -= 1
                        scheduleQuickScan()
                    }
                }
            }
            guard currentGeneration == generation else { return }
            switch result {
            case .failure:
                status = "Cannot read the Screenshot save folder. Allow folder access in System Settings → Privacy & Security → Files and Folders, or choose an accessible Screenshot destination."
            case .success(let candidates):
                if status.isEmpty || status.hasPrefix("Cannot read") {
                    status = "Watching new \(screenshots ? "screenshots" : "screen recordings") in \(currentDirectory.lastPathComponent)."
                }
                let ready = tracker.update(candidates, now: Date(), stabilityInterval: screenshots ? 0.15 : 3)
                for candidate in ready {
                    let playable: Bool
                    if screenshots {
                        playable = candidate.size <= ClipboardPolicy.maxImageBytes
                    } else {
                        let asset = AVURLAsset(url: candidate.url)
                        playable = (try? await asset.load(.isPlayable)) == true
                    }
                    guard currentGeneration == generation else { return }
                    guard playable else { continue }
                    // Recheck after async validation: a growing file isn't done.
                    guard let latest = try? ScreenRecordingCandidate.read(candidate.url),
                          latest == candidate else { continue }
                    if await onRecording(candidate.url) {
                        tracker.markCopied(candidate.url)
                        status = screenshots ? "Screenshot copied. Ready to paste." : "Screen recording copied. Ready to paste."
                    } else {
                        status = "Could not copy the saved capture. Check access to the Screenshot folder. Retrying…"
                    }
                }
            }
        }
    }
}

struct ScreenRecordingCandidate: Equatable, Sendable {
    let url: URL
    let size: Int
    let modified: Date

    static func scan(directory: URL, screenshots: Bool = false) throws -> [Self] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return urls.compactMap { url in
            let extensions = screenshots ? ["png", "jpg", "jpeg", "tiff", "heic"] : ["mov"]
            guard extensions.contains(url.pathExtension.lowercased()) else { return nil }
            // macOS stamps captures with this metadata. The standard English
            // filename also handles saves before metadata indexing has finished.
            let nameMatches = screenshots
                ? (url.lastPathComponent.hasPrefix("Screenshot ") || url.lastPathComponent.hasPrefix("Screen Shot "))
                : url.lastPathComponent.hasPrefix("Screen Recording ")
            let captureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
            let markedCapture = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return false }
                return getxattr(path, captureAttribute, nil, 0, 0, XATTR_NOFOLLOW) > 0
            }
            guard nameMatches || markedCapture else { return nil }
            return try? read(url)
        }
    }

    static func read(_ url: URL) throws -> Self? {
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        let values = try freshURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0,
              let modified = values.contentModificationDate else { return nil }
        return Self(url: url, size: size, modified: modified)
    }
}

struct ScreenRecordingTracker {
    private var initialized = false
    private var seen = Set<URL>()
    private var pending: [URL: (candidate: ScreenRecordingCandidate, stableSince: Date)] = [:]

    var hasPending: Bool { !pending.isEmpty }

    mutating func update(_ candidates: [ScreenRecordingCandidate], now: Date,
                         stabilityInterval: TimeInterval = 3) -> [ScreenRecordingCandidate] {
        guard initialized else {
            seen = Set(candidates.map(\.url))
            initialized = true
            return []
        }
        let present = Set(candidates.map(\.url))
        pending = pending.filter { present.contains($0.key) }
        var ready: [ScreenRecordingCandidate] = []
        for candidate in candidates where !seen.contains(candidate.url) {
            if let previous = pending[candidate.url], previous.candidate == candidate {
                if now.timeIntervalSince(previous.stableSince) >= stabilityInterval {
                    ready.append(candidate)
                }
            } else {
                pending[candidate.url] = (candidate, now)
            }
        }
        return ready.sorted { $0.modified < $1.modified }
    }

    mutating func markCopied(_ url: URL) {
        seen.insert(url)
        pending.removeValue(forKey: url)
    }
}
