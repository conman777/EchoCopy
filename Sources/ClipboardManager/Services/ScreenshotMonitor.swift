import AppKit
import Foundation

/// Monitors for new screenshots and automatically copies them to clipboard
final class ScreenshotMonitor: ObservableObject {
    private var timer: Timer?
    private var lastCheckedScreenshots: Set<String> = []
    private let fileManager = FileManager.default

    /// Paths to monitor for screenshots
    private var monitorPaths: [URL] {
        var paths: [URL] = []

        // Desktop (default location)
        if let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first {
            paths.append(desktopURL)
        }

        // Screenshots folder (if user changed default location)
        if let picturesURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first {
            let screenshotsURL = picturesURL.appendingPathComponent("Screenshots")
            if fileManager.fileExists(atPath: screenshotsURL.path) {
                paths.append(screenshotsURL)
            }
        }

        return paths
    }

    /// Start monitoring for new screenshots
    func startMonitoring() {
        // Initialize with current screenshots to avoid copying old ones
        scanCurrentScreenshots()

        // Check for new screenshots at configured interval
        timer = Timer.scheduledTimer(
            withTimeInterval: Constants.ScreenshotMonitor.checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForNewScreenshots()
        }

        // Ensure timer is added to main run loop
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        NSLog("📸 ScreenshotMonitor: Started monitoring for screenshots")
    }

    /// Stop monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        NSLog("📸 ScreenshotMonitor: Stopped monitoring")
    }

    /// Scan current screenshots to establish baseline
    private func scanCurrentScreenshots() {
        lastCheckedScreenshots.removeAll()

        for path in monitorPaths {
            let screenshots = findScreenshots(in: path)
            lastCheckedScreenshots.formUnion(screenshots.map { $0.path })
        }

        NSLog("📸 ScreenshotMonitor: Found \(lastCheckedScreenshots.count) existing screenshots")
    }

    /// Check for new screenshots since last check
    private func checkForNewScreenshots() {
        NSLog("📸 ScreenshotMonitor: Checking for new screenshots...")
        var newScreenshots: [URL] = []

        for path in monitorPaths {
            let currentScreenshots = findScreenshots(in: path)
            NSLog("📸 ScreenshotMonitor: Found \(currentScreenshots.count) total screenshots in \(path.path)")

            for screenshot in currentScreenshots {
                let screenshotPath = screenshot.path

                // Check if this is a new screenshot
                if !lastCheckedScreenshots.contains(screenshotPath) {
                    NSLog("📸 ScreenshotMonitor: New screenshot detected: \(screenshot.lastPathComponent)")
                    // Verify file was created very recently (within last 10 seconds)
                    if isRecentFile(screenshot) {
                        if isFileReady(screenshot) {
                            NSLog("📸 ScreenshotMonitor: Screenshot is ready, will auto-copy")
                            newScreenshots.append(screenshot)
                            lastCheckedScreenshots.insert(screenshotPath)
                        } else {
                            NSLog("📸 ScreenshotMonitor: Screenshot not ready yet, will retry next pass")
                        }
                    } else {
                        NSLog("📸 ScreenshotMonitor: Screenshot too old, skipping")
                    }
                }
            }
        }

        NSLog("📸 ScreenshotMonitor: Found \(newScreenshots.count) new screenshots to copy")

        // Copy new screenshots to clipboard
        for screenshot in newScreenshots {
            copyScreenshotToClipboard(screenshot)
        }
    }

    /// Find screenshot files in a directory
    private func findScreenshots(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var screenshots: [URL] = []

        for case let fileURL as URL in enumerator {
            // Check if file matches screenshot naming pattern
            if isScreenshotFile(fileURL) {
                screenshots.append(fileURL)
            }
        }

        return screenshots
    }

    /// Check if a file is a screenshot based on naming pattern
    private func isScreenshotFile(_ url: URL) -> Bool {
        let filename = url.lastPathComponent
        let pathExtension = url.pathExtension.lowercased()

        // macOS screenshot patterns:
        // "Screenshot 2025-10-24 at 4.30.45 PM.png"
        // "Screen Shot 2025-10-24 at 4.30.45 PM.png"
        let isScreenshotName = filename.hasPrefix("Screenshot ") || filename.hasPrefix("Screen Shot ")
        let isPNG = pathExtension == "png"

        return isScreenshotName && isPNG
    }

    /// Check if file was created recently
    private func isRecentFile(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let creationDate = attributes[.creationDate] as? Date else {
            return false
        }

        let ageInSeconds = Date().timeIntervalSince(creationDate)
        return ageInSeconds < Constants.ScreenshotMonitor.maxFileAge
    }

    /// Determine if the screenshot file is fully written and ready
    private func isFileReady(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? UInt64 else {
            return false
        }

        guard fileSize > 0 else {
            return false
        }

        guard let creationDate = attributes[.creationDate] as? Date else {
            return false
        }

        let ageInSeconds = Date().timeIntervalSince(creationDate)
        return ageInSeconds >= Constants.ScreenshotMonitor.minReadyAge
    }

    /// Copy screenshot image to clipboard
    private func copyScreenshotToClipboard(_ url: URL) {
        // Read image from file
        guard let image = NSImage(contentsOf: url) else {
            NSLog("📸 ScreenshotMonitor: Failed to read image from \(url.lastPathComponent)")
            return
        }

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var objects: [NSPasteboardWriting] = []
        objects.append(url as NSURL)
        objects.append(image)

        pasteboard.writeObjects(objects)

        if let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)

            if let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                pasteboard.setData(pngData, forType: .png)
            }
        }

        pasteboard.setString(url.path, forType: .string)

        NSLog("📸 ScreenshotMonitor: Auto-copied screenshot to clipboard: \(url.lastPathComponent)")

        // Optional: Show notification
        showNotification(for: url)
    }

    /// Show notification that screenshot was copied
    private func showNotification(for url: URL) {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = "Screenshot Copied"
            notification.informativeText = "Screenshot automatically copied to clipboard"
            notification.soundName = nil // Silent

            NSUserNotificationCenter.default.deliver(notification)
        }
    }

    deinit {
        stopMonitoring()
    }
}
