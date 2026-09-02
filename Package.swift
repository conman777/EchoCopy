// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EchoCopy",
    platforms: [
        .macOS(.v13)
  ],
    products: [
        .executable(
            name: "EchoCopy",
            targets: ["EchoCopy"]
        )
    ],
    targets: [
        .executableTarget(
            name: "EchoCopy",
            exclude: [
                "Info.plist"
            ]
        ),
        .testTarget(
            name: "EchoCopyTests",
            dependencies: ["EchoCopy"]
        )
    ]
)
