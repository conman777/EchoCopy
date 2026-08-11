import AppKit
import Carbon.HIToolbox
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import EchoCopy

final class ScreenshotCaptureCoordinatorTests: XCTestCase {
    func testStandardScreenshotShortcutRecognition() {
        let commandShift: CGEventFlags = [.maskCommand, .maskShift]

        XCTAssertTrue(
            ScreenshotShortcutPolicy.isStandardScreenshotShortcut(
                keyCode: CGKeyCode(kVK_ANSI_3),
                flags: commandShift
            )
        )
        XCTAssertTrue(
            ScreenshotShortcutPolicy.isStandardScreenshotShortcut(
                keyCode: CGKeyCode(kVK_ANSI_4),
                flags: commandShift
            )
        )
        XCTAssertTrue(
            ScreenshotShortcutPolicy.isStandardScreenshotShortcut(
                keyCode: CGKeyCode(kVK_ANSI_6),
                flags: commandShift
            )
        )
        XCTAssertFalse(
            ScreenshotShortcutPolicy.isStandardScreenshotShortcut(
                keyCode: CGKeyCode(kVK_ANSI_5),
                flags: commandShift
            )
        )
        XCTAssertFalse(
            ScreenshotShortcutPolicy.isStandardScreenshotShortcut(
                keyCode: CGKeyCode(kVK_ANSI_3),
                flags: commandShift.union(.maskControl)
            )
        )
    }

    func testScreenshotReplacementIncludesRealControlTransition() throws {
        let originalFlags: CGEventFlags = [.maskCommand, .maskShift]
        let replacement = try XCTUnwrap(
            ScreenshotShortcutRemapper.makeClipboardShortcutReplacement(
                keyCode: CGKeyCode(kVK_ANSI_4),
                flags: originalFlags
            )
        )

        XCTAssertEqual(replacement.controlDown.type, .flagsChanged)
        XCTAssertEqual(
            CGKeyCode(replacement.controlDown.getIntegerValueField(.keyboardEventKeycode)),
            CGKeyCode(kVK_Control)
        )
        XCTAssertEqual(replacement.shortcutDown.type, .keyDown)
        XCTAssertEqual(replacement.shortcutUp.type, .keyUp)
        XCTAssertEqual(
            CGKeyCode(replacement.shortcutDown.getIntegerValueField(.keyboardEventKeycode)),
            CGKeyCode(kVK_ANSI_4)
        )
        XCTAssertEqual(replacement.controlUp.type, .flagsChanged)

        for event in replacement.events {
            XCTAssertTrue(
                ScreenshotShortcutRemapper.isSyntheticScreenshotEvent(event)
            )
        }
        XCTAssertTrue(replacement.controlDown.flags.contains(.maskControl))
        XCTAssertTrue(replacement.shortcutDown.flags.contains(.maskControl))
        XCTAssertTrue(replacement.shortcutUp.flags.contains(.maskControl))
        XCTAssertFalse(replacement.controlUp.flags.contains(.maskControl))
    }

    func testPendingScreenshotIsConsumedExactlyOnce() throws {
        let defaults = makeUserDefaults()
        let destination = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinator = ScreenshotCaptureCoordinator(
            userDefaults: defaults,
            pendingLifetime: 30,
            screenshotTargetProvider: { "file" },
            destinationDirectoryProvider: { destination }
        )

        XCTAssertTrue(
            coordinator.beginAutomaticClipboardCapture(
                startingPasteboardChangeCount: 10,
                now: now
            )
        )
        XCTAssertFalse(
            coordinator.isAwaitingScreenshot(
                pasteboardChangeCount: 10,
                now: now
            )
        )
        XCTAssertTrue(
            coordinator.isAwaitingScreenshot(
                pasteboardChangeCount: 11,
                now: now
            )
        )

        let request = try XCTUnwrap(
            coordinator.consumeScreenshot(
                pasteboardChangeCount: 11,
                now: now
            )
        )
        XCTAssertEqual(request.destinationDirectory, destination)
        XCTAssertNil(
            coordinator.consumeScreenshot(
                pasteboardChangeCount: 11,
                now: now
            )
        )
    }

    func testDisabledOrNonFileScreenshotTargetIsNotRedirected() {
        let defaults = makeUserDefaults()
        defaults.set(
            false,
            forKey: ScreenshotCaptureCoordinator.automaticClipboardPreferenceKey
        )
        let disabledCoordinator = ScreenshotCaptureCoordinator(
            userDefaults: defaults,
            screenshotTargetProvider: { "file" }
        )
        XCTAssertFalse(
            disabledCoordinator.beginAutomaticClipboardCapture(
                startingPasteboardChangeCount: 1
            )
        )

        defaults.set(
            true,
            forKey: ScreenshotCaptureCoordinator.automaticClipboardPreferenceKey
        )
        let previewCoordinator = ScreenshotCaptureCoordinator(
            userDefaults: defaults,
            screenshotTargetProvider: { "preview" }
        )
        XCTAssertFalse(
            previewCoordinator.beginAutomaticClipboardCapture(
                startingPasteboardChangeCount: 1
            )
        )
    }

    func testPendingScreenshotExpires() {
        let defaults = makeUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinator = ScreenshotCaptureCoordinator(
            userDefaults: defaults,
            pendingLifetime: 2,
            screenshotTargetProvider: { "file" }
        )

        XCTAssertTrue(
            coordinator.beginAutomaticClipboardCapture(
                startingPasteboardChangeCount: 3,
                now: now
            )
        )
        XCTAssertFalse(
            coordinator.isAwaitingScreenshot(
                pasteboardChangeCount: 4,
                now: now.addingTimeInterval(3)
            )
        )
    }

    func testScreenshotFileSaverCreatesPNGWithoutOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoCopyScreenshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2,
                pixelsHigh: 1,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let tiffData = try XCTUnwrap(bitmap.tiffRepresentation)
        let request = ScreenshotSaveRequest(destinationDirectory: directory)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try XCTUnwrap(
            ScreenshotFileSaver.save(
                imageData: tiffData,
                request: request,
                date: date
            )
        )
        let second = try XCTUnwrap(
            ScreenshotFileSaver.save(
                imageData: tiffData,
                request: request,
                date: date
            )
        )

        XCTAssertNotEqual(first.fileURL, second.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.fileURL.path))
        XCTAssertEqual(first.fileURL.pathExtension, "png")

        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(first.imageData as CFData, nil)
        )
        XCTAssertEqual(
            CGImageSourceGetType(source) as String?,
            UTType.png.identifier
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EchoCopyTests.ScreenshotCapture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
