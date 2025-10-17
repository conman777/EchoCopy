// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ClipboardManager",
            targets: ["ClipboardManager"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            exclude: [
                "Info.plist"
            ],
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"], .when(configuration: .debug)),
            ]
        )
    ]
)
