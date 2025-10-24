// swift-tools-version: 5.9
import PackageDescription

/// ClipboardManager - A lightweight clipboard history manager for macOS
///
/// Features:
/// - Clipboard history tracking (up to 500 items)
/// - Search functionality
/// - Pin/unpin frequently used items
/// - Global keyboard shortcuts (Option+V, Cmd+Alt+1-9)
/// - Menu bar integration
/// - Privacy-focused: No network access, local storage only
///
/// Requirements:
/// - macOS 13.0 or later
/// - Swift 5.9 or later
/// - Accessibility permissions for global shortcuts
///
/// Build: `swift build -c release`
/// Run: `swift run ClipboardManager`
///
/// Documentation:
/// - README.md - Project overview
/// - docs/architecture/SYSTEM_ARCHITECTURE.md - Architecture details
/// - docs/development/SETUP.md - Development setup
/// - docs/development/SWIFT_CONVENTIONS.md - Code standards
///
/// Quality Tools:
/// - SwiftFormat: `swiftformat Sources/`
/// - SwiftLint: `swiftlint lint`
/// - Pre-commit hooks: `.githooks/setup.sh`

let package = Package(
    name: "ClipboardManager",
    platforms: [
        .macOS(.v13)  // Minimum deployment target
    ],
    products: [
        .executable(
            name: "ClipboardManager",
            targets: ["ClipboardManager"]
        )
    ],
    dependencies: [
        // No external dependencies - uses only Apple frameworks
    ],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: [],
            swiftSettings: [
                // Strict mode for type checking
                .unsafeFlags(["-strict-concurrency=complete"]),
                // Optimization for debug builds: fast compilation
                .unsafeFlags(["-Onone"], .when(configuration: .debug)),
                // Optimization for release builds: size
                .unsafeFlags(["-Osize"], .when(configuration: .release)),
            ],
            linkerSettings: [
                // Link with AppKit framework for macOS integration
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
