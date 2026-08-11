import CoreGraphics
import Carbon.HIToolbox
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotSaveRequest: Sendable {
    let destinationDirectory: URL
}

struct SavedScreenshot: Sendable {
    let fileURL: URL
    let imageData: Data
}

enum ScreenshotShortcutPolicy {
    static func isStandardScreenshotShortcut(
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        guard flags.contains(.maskCommand),
              flags.contains(.maskShift),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskControl) else {
            return false
        }

        // Shift-Command-3 captures the displays, Shift-Command-4 starts an
        // interactive selection/window capture, and Shift-Command-6 captures
        // the Touch Bar on Macs that provide one. Shift-Command-5 opens the
        // Screenshot app rather than completing a capture, so it is left alone.
        return [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_6]
            .map(CGKeyCode.init)
            .contains(keyCode)
    }
}

struct ScreenshotShortcutReplacement {
    let controlDown: CGEvent
    let shortcutDown: CGEvent
    let shortcutUp: CGEvent
    let controlUp: CGEvent

    var events: [CGEvent] {
        [controlDown, shortcutDown, shortcutUp, controlUp]
    }
}

/// Creates a real Control modifier transition around the replacement shortcut.
/// Screenshot Services observes keyboard state as well as event flags, so only
/// adding `.maskControl` to the number-key event is not reliable.
enum ScreenshotShortcutRemapper {
    private static let syntheticEventMarker: Int64 = 0x4543_484F_5343_52

    static func isSyntheticScreenshotEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker
    }

    static func makeClipboardShortcutReplacement(
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> ScreenshotShortcutReplacement? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let controlDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_Control),
                  keyDown: true
              ),
              let shortcutDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: true
              ),
              let shortcutUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: false
              ),
              let controlUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_Control),
                  keyDown: false
              ) else {
            return nil
        }

        let clipboardFlags = flags.union(.maskControl)
        controlDown.flags = clipboardFlags
        shortcutDown.flags = clipboardFlags
        shortcutUp.flags = clipboardFlags
        controlUp.flags = flags.subtracting(.maskControl)

        let replacement = ScreenshotShortcutReplacement(
            controlDown: controlDown,
            shortcutDown: shortcutDown,
            shortcutUp: shortcutUp,
            controlUp: controlUp
        )
        for event in replacement.events {
            event.setIntegerValueField(
                .eventSourceUserData,
                value: syntheticEventMarker
            )
        }
        return replacement
    }
}

/// Coordinates a screenshot shortcut with the next image pasteboard change.
/// EchoCopy changes the shortcut to its Control variant, which makes macOS put
/// the capture on the clipboard. The clipboard monitor then creates the normal
/// screenshot file itself, avoiding any need to read the Desktop folder.
final class ScreenshotCaptureCoordinator: @unchecked Sendable {
    static let shared = ScreenshotCaptureCoordinator()
    static let automaticClipboardPreferenceKey = "AutomaticallyCopyScreenshots"

    private struct PendingCapture {
        let startingPasteboardChangeCount: Int
        let expiresAt: Date
        let destinationDirectory: URL
    }

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private let pendingLifetime: TimeInterval
    private let screenshotTargetProvider: () -> String?
    private let destinationDirectoryProvider: () -> URL
    private var pendingCapture: PendingCapture?

    init(
        userDefaults: UserDefaults = .standard,
        pendingLifetime: TimeInterval = 120,
        screenshotTargetProvider: @escaping () -> String? = {
            CFPreferencesCopyAppValue(
                "target-screenshot" as CFString,
                "com.apple.screencapture" as CFString
            ) as? String
        },
        destinationDirectoryProvider: @escaping () -> URL = {
            ScreenshotCaptureCoordinator.systemScreenshotDirectory()
        }
    ) {
        self.userDefaults = userDefaults
        self.pendingLifetime = pendingLifetime
        self.screenshotTargetProvider = screenshotTargetProvider
        self.destinationDirectoryProvider = destinationDirectoryProvider
    }

    /// Returns true only when EchoCopy should add Control to the standard
    /// screenshot shortcut. A non-file Screenshot target is left untouched so
    /// EchoCopy never overrides destinations such as Preview or Mail.
    func beginAutomaticClipboardCapture(
        startingPasteboardChangeCount: Int,
        now: Date = Date()
    ) -> Bool {
        guard automaticallyCopiesScreenshots,
              (screenshotTargetProvider()?.lowercased() ?? "file") == "file" else {
            return false
        }

        let pending = PendingCapture(
            startingPasteboardChangeCount: startingPasteboardChangeCount,
            expiresAt: now.addingTimeInterval(pendingLifetime),
            destinationDirectory: destinationDirectoryProvider()
        )

        lock.lock()
        pendingCapture = pending
        lock.unlock()
        return true
    }

    func isAwaitingScreenshot(
        pasteboardChangeCount: Int,
        now: Date = Date()
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let pendingCapture else { return false }
        guard now <= pendingCapture.expiresAt else {
            self.pendingCapture = nil
            return false
        }

        return pasteboardChangeCount != pendingCapture.startingPasteboardChangeCount
    }

    func consumeScreenshot(
        pasteboardChangeCount: Int,
        now: Date = Date()
    ) -> ScreenshotSaveRequest? {
        lock.lock()
        defer { lock.unlock() }

        guard let pendingCapture,
              now <= pendingCapture.expiresAt,
              pasteboardChangeCount != pendingCapture.startingPasteboardChangeCount else {
            if let pendingCapture, now > pendingCapture.expiresAt {
                self.pendingCapture = nil
            }
            return nil
        }

        self.pendingCapture = nil
        return ScreenshotSaveRequest(
            destinationDirectory: pendingCapture.destinationDirectory
        )
    }

    func cancelIfPasteboardChanged(to changeCount: Int) {
        lock.lock()
        if let pendingCapture,
           changeCount != pendingCapture.startingPasteboardChangeCount {
            self.pendingCapture = nil
        }
        lock.unlock()
    }

    func cancelPendingCapture() {
        lock.lock()
        pendingCapture = nil
        lock.unlock()
    }

    private var automaticallyCopiesScreenshots: Bool {
        guard userDefaults.object(
            forKey: Self.automaticClipboardPreferenceKey
        ) != nil else {
            return true
        }
        return userDefaults.bool(forKey: Self.automaticClipboardPreferenceKey)
    }

    private static func systemScreenshotDirectory() -> URL {
        if let location = CFPreferencesCopyAppValue(
            "location" as CFString,
            "com.apple.screencapture" as CFString
        ) as? String,
           !location.isEmpty {
            if let locationURL = URL(string: location), locationURL.isFileURL {
                return locationURL.standardizedFileURL
            }

            let expandedPath = (location as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expandedPath, isDirectory: true)
                .standardizedFileURL
        }

        return FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Desktop", isDirectory: true)
    }
}

enum ScreenshotFileSaver {
    static func save(
        imageData: Data,
        request: ScreenshotSaveRequest,
        date: Date = Date()
    ) -> SavedScreenshot? {
        let convertedPNGData = pngData(from: imageData)
        let normalizedData = convertedPNGData ?? imageData
        let fileExtension = convertedPNGData == nil
            ? sourceFileExtension(for: imageData)
            : "png"
        let baseFilename = screenshotFilename(for: date)

        for attempt in 0..<10 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let fileURL = request.destinationDirectory
                .appendingPathComponent(baseFilename + suffix)
                .appendingPathExtension(fileExtension)

            do {
                try normalizedData.write(
                    to: fileURL,
                    options: .withoutOverwriting
                )
                return SavedScreenshot(
                    fileURL: fileURL,
                    imageData: normalizedData
                )
            } catch CocoaError.fileWriteFileExists {
                continue
            } catch {
                return nil
            }
        }

        return nil
    }

    private static func pngData(from imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let sourceType = CGImageSourceGetType(source) else {
            return nil
        }

        if sourceType as String == UTType.png.identifier {
            return imageData
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationData as Data
    }

    private static func sourceFileExtension(for imageData: Data) -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              let type = UTType(sourceType as String),
              let fileExtension = type.preferredFilenameExtension else {
            return "png"
        }
        return fileExtension
    }

    private static func screenshotFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'Screenshot' yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }
}
