import AppKit
import Foundation
import XCTest
@testable import EchoCopy

@MainActor
final class PasteboardWriteTrackerTests: XCTestCase {
    func testSuccessfulWriteIsConsumedExactlyOnce() {
        let pasteboard = makePasteboard()
        let tracker = PasteboardWriteTracker()
        let item = ClipboardItem(content: "copied by EchoCopy", contentType: .text)

        XCTAssertTrue(
            PasteboardWriter.write(
                item,
                to: pasteboard,
                writeTracker: tracker
            )
        )
        XCTAssertEqual(pasteboard.string(forType: .string), item.content)
        XCTAssertTrue(tracker.consumeIfInternal(changeCount: pasteboard.changeCount))
        XCTAssertFalse(tracker.consumeIfInternal(changeCount: pasteboard.changeCount))
    }

    func testInvalidImageDoesNotClearExistingClipboardContents() {
        let pasteboard = makePasteboard()
        let tracker = PasteboardWriteTracker()
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let originalChangeCount = pasteboard.changeCount

        let invalidImage = ClipboardItem(
            content: Data([0x00, 0x01, 0x02]).base64EncodedString(),
            contentType: .image
        )

        XCTAssertFalse(
            PasteboardWriter.write(
                invalidImage,
                to: pasteboard,
                writeTracker: tracker
            )
        )
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
        XCTAssertEqual(pasteboard.changeCount, originalChangeCount)
        XCTAssertFalse(tracker.consumeIfInternal(changeCount: pasteboard.changeCount))
    }

    func testValidImageWritesItsNativePasteboardRepresentation() throws {
        let pasteboard = makePasteboard()
        let tracker = PasteboardWriteTracker()
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 1,
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
        if let bitmapData = bitmap.bitmapData {
            bitmapData[0] = 0
            bitmapData[1] = 122
            bitmapData[2] = 255
            bitmapData[3] = 255
        }
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let item = ClipboardItem(
            content: pngData.base64EncodedString(),
            contentType: .image,
            filename: "image.png"
        )

        XCTAssertTrue(
            PasteboardWriter.write(
                item,
                to: pasteboard,
                writeTracker: tracker
            )
        )
        XCTAssertEqual(pasteboard.data(forType: .png), pngData)
        XCTAssertTrue(tracker.consumeIfInternal(changeCount: pasteboard.changeCount))
    }

    func testMismatchedExternalChangeIsNotSuppressed() {
        let tracker = PasteboardWriteTracker()
        tracker.recordInternalWrite(changeCount: 10)

        XCTAssertFalse(tracker.consumeIfInternal(changeCount: 11))
        XCTAssertFalse(tracker.consumeIfInternal(changeCount: 10))
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("EchoCopyTests.\(UUID().uuidString)"))
    }
}
