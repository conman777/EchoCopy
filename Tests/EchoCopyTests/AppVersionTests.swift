import Foundation
import XCTest
@testable import EchoCopy

final class AppVersionTests: XCTestCase {
    func testSourceBundleMetadataUsesVersionOneZeroSeven() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = repositoryRoot
            .appendingPathComponent("Sources/EchoCopy/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.0.7")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "7")
    }
}
