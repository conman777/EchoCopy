// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snaply",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Snaply",
            targets: ["Snaply"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Snaply",
            exclude: [
                "Info.plist"
            ],
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"], .when(configuration: .debug)),
            ]
        )
    ]
)
