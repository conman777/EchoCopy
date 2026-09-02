import Foundation
import XCTest
@testable import EchoCopy

final class AppVersionTests: XCTestCase {
    func testPublishedOneZeroSixIsNotAnUpdateForOneZeroSeven() {
        XCTAssertFalse(
            UpdateVersionPolicy.updateAvailable(
                latest: "v1.0.6",
                current: "1.0.7"
            )
        )
    }

    func testOnlyStrictlyNewerNumericVersionsAreUpdates() {
        XCTAssertFalse(
            UpdateVersionPolicy.updateAvailable(
                latest: "1.0.7",
                current: "1.0.7"
            )
        )
        XCTAssertFalse(
            UpdateVersionPolicy.updateAvailable(
                latest: "1.0.7.0",
                current: "1.0.7"
            )
        )
        XCTAssertTrue(
            UpdateVersionPolicy.updateAvailable(
                latest: "1.0.8",
                current: "1.0.7"
            )
        )
    }

    func testMalformedReleaseTagsDoNotProduceUpdatePrompts() {
        XCTAssertFalse(
            UpdateVersionPolicy.updateAvailable(
                latest: "release-1.0.8",
                current: "1.0.7"
            )
        )
        XCTAssertFalse(
            UpdateVersionPolicy.updateAvailable(
                latest: "1.0.beta",
                current: "1.0.7"
            )
        )
    }

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
