import Foundation
import XCTest
@testable import EchoCopy

final class ClipboardPolicyTests: XCTestCase {
    func testClipboardAppTransitionAllowsSafeCopiesAndBlocksExcludedApps() {
        let excludedApps: Set<String> = ["com.password.manager"]

        XCTAssertTrue(
            ClipboardPolicy.canStoreClipboardChange(
                previousBundleID: "com.apple.Safari",
                currentBundleID: "com.apple.Safari",
                excludedBundleIDs: excludedApps
            )
        )
        XCTAssertTrue(
            ClipboardPolicy.canStoreClipboardChange(
                previousBundleID: "com.apple.Safari",
                currentBundleID: "com.echocopy.app",
                excludedBundleIDs: excludedApps
            )
        )
        XCTAssertFalse(
            ClipboardPolicy.canStoreClipboardChange(
                previousBundleID: "com.password.manager",
                currentBundleID: "com.echocopy.app",
                excludedBundleIDs: excludedApps
            )
        )
        XCTAssertFalse(
            ClipboardPolicy.canStoreClipboardChange(
                previousBundleID: "com.apple.Safari",
                currentBundleID: "com.password.manager",
                excludedBundleIDs: excludedApps
            )
        )
        XCTAssertFalse(
            ClipboardPolicy.canStoreClipboardChange(
                previousBundleID: nil,
                currentBundleID: "com.apple.Safari",
                excludedBundleIDs: excludedApps
            )
        )
        XCTAssertFalse(
            ClipboardPolicy.canStoreClipboardChange(
                previousBundleID: "com.apple.Safari",
                currentBundleID: nil,
                excludedBundleIDs: excludedApps
            )
        )
    }

    func testSensitivePasteboardAnnotationsAreSuppressed() {
        XCTAssertTrue(
            ClipboardPolicy.containsSuppressedPasteboardType([
                "public.utf8-plain-text",
                "org.nspasteboard.ConcealedType"
            ])
        )
        XCTAssertTrue(
            ClipboardPolicy.containsSuppressedPasteboardType([
                "org.nspasteboard.TransientType"
            ])
        )
        XCTAssertFalse(
            ClipboardPolicy.containsSuppressedPasteboardType([
                "public.utf8-plain-text"
            ])
        )
    }

    func testBoundedTextAndRichTextAreAccepted() {
        XCTAssertTrue(
            ClipboardPolicy.acceptsStoredItem(
                content: "hello",
                contentType: .text,
                rtfContent: Data([1, 2, 3]).base64EncodedString(),
                filename: "snippet.txt"
            )
        )

        let oversizedText = String(repeating: "a", count: ClipboardPolicy.maxTextBytes + 1)
        XCTAssertFalse(
            ClipboardPolicy.acceptsStoredItem(
                content: oversizedText,
                contentType: .text,
                rtfContent: nil
            )
        )

        let oversizedRTF = String(repeating: "A", count: ((ClipboardPolicy.maxRTFBytes + 2) / 3) * 4 + 1)
        XCTAssertFalse(
            ClipboardPolicy.acceptsStoredItem(
                content: "hello",
                contentType: .text,
                rtfContent: oversizedRTF
            )
        )
    }

    func testImagePayloadMustBeValidAndBounded() {
        let smallImage = Data([0, 1, 2, 3]).base64EncodedString()
        XCTAssertTrue(
            ClipboardPolicy.acceptsStoredItem(
                content: smallImage,
                contentType: .image,
                rtfContent: nil
            )
        )

        let oversizedImage = String(
            repeating: "A",
            count: ((ClipboardPolicy.maxImageBytes + 2) / 3) * 4 + 1
        )
        XCTAssertFalse(
            ClipboardPolicy.acceptsStoredItem(
                content: oversizedImage,
                contentType: .image,
                rtfContent: nil
            )
        )
        XCTAssertFalse(
            ClipboardPolicy.acceptsStoredItem(
                content: "not-base64",
                contentType: .image,
                rtfContent: nil
            )
        )
    }

    func testPasteboardPayloadBoundsAreInclusive() {
        XCTAssertTrue(ClipboardPolicy.acceptsImagePasteboardData(byteCount: ClipboardPolicy.maxImageBytes))
        XCTAssertFalse(ClipboardPolicy.acceptsImagePasteboardData(byteCount: ClipboardPolicy.maxImageBytes + 1))
        XCTAssertTrue(ClipboardPolicy.acceptsRTFPasteboardData(byteCount: ClipboardPolicy.maxRTFBytes))
        XCTAssertFalse(ClipboardPolicy.acceptsRTFPasteboardData(byteCount: ClipboardPolicy.maxRTFBytes + 1))
    }
}
