import AppKit
import XCTest
@testable import EchoCopy

final class ClipboardThumbnailDecoderTests: XCTestCase {
    func testThumbnailHonorsMaximumPixelSize() throws {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 100,
                pixelsHigh: 50,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let pngData = try XCTUnwrap(
            bitmap.representation(using: .png, properties: [:])
        )

        let thumbnail = try XCTUnwrap(
            ClipboardThumbnailDecoder.makeThumbnail(
                fromBase64: pngData.base64EncodedString(),
                maximumPixelSize: 20
            )
        )

        XCTAssertEqual(thumbnail.width, 20)
        XCTAssertEqual(thumbnail.height, 10)
    }

    func testInvalidImageReturnsNil() {
        XCTAssertNil(
            ClipboardThumbnailDecoder.makeThumbnail(
                fromBase64: "not valid base64"
            )
        )
    }
}
