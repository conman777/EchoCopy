# Build and Deployment Guide

## Building the Application

### Development Build

Build without optimization (faster compile, better debugging):

```bash
swift build
```

Output: `.build/debug/ClipboardManager`

### Release Build

Build with optimizations (slower to compile, faster runtime):

```bash
swift build -c release
```

Output: `.build/release/ClipboardManager`

### Running the App

```bash
# From debug build
./.build/debug/ClipboardManager

# From release build
./.build/release/ClipboardManager

# Or via Swift directly
swift run ClipboardManager
```

## Code Quality Gates (Pre-Build Checklist)

Before building for distribution:

### 1. Format Code
```bash
swiftformat Sources/
git diff Sources/  # Verify formatting changes
```

### 2. Lint Code
```bash
swiftlint lint
```

Fix all warnings - the build should have zero warnings.

### 3. Verify Build Succeeds
```bash
swift build -c release
```

### 4. Manual Testing
```bash
./.build/release/ClipboardManager
# Test clipboard monitoring
# Test keyboard shortcuts
# Test menu bar
# Test popup window
```

## Distribution

### Creating a Standalone Executable

The built binary can be distributed directly:

```bash
# Release build
swift build -c release

# Copy to a distribution location
cp .build/release/ClipboardManager ~/Downloads/ClipboardManager
```

### Notarization (for Mac App Store / Verified Distribution)

For distribution outside the sandbox, notarization is optional but recommended:

```bash
# Sign the binary
codesign -s - .build/release/ClipboardManager

# Submit for notarization (requires Apple Developer account)
xcrun notarytool submit .build/release/ClipboardManager \
  --apple-id your-apple-id@example.com \
  --password your-app-specific-password \
  --team-id TEAM_ID_HERE
```

See `DISTRIBUTION_GUIDE.md` for complete notarization details.

### Creating an App Bundle (if desired)

If you want a `.app` bundle for easier distribution:

```bash
mkdir -p ClipboardManager.app/Contents/MacOS
cp .build/release/ClipboardManager ClipboardManager.app/Contents/MacOS/

# Create minimal Info.plist
cat > ClipboardManager.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClipboardManager</string>
    <key>CFBundleIdentifier</key>
    <string>com.conordart.clipboardmanager</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
</dict>
</plist>
EOF
```

## Deployment Strategies

### Option 1: Direct Binary Distribution
**Best for**: Developers, power users

- Distribute `.build/release/ClipboardManager` executable
- Users run directly: `./ClipboardManager`
- Smallest distribution size
- Requires accessibility permissions on first run

### Option 2: Homebrew Package
**Best for**: Wide distribution to macOS users

```bash
# Submit to Homebrew or create homebrew-tap
brew install clipboard-manager
```

### Option 3: GitHub Releases
**Best for**: Open source distribution

1. Build release binary
2. Create GitHub release
3. Attach binary to release
4. Users download and run

### Option 4: Mac App Store
**Best for**: Official app store distribution

Requires:
- Apple Developer account ($99/year)
- Code signing certificate
- App Store submission process
- Sandboxing review

See `DISTRIBUTION_GUIDE.md` for complete details.

## Version Management

Follow Semantic Versioning (MAJOR.MINOR.PATCH):

**Version location**: `Sources/ClipboardManager/Utilities/Constants.swift`

```swift
enum Constants {
    static let appVersion = "1.0.0"
}
```

Or in Package.swift:
```swift
let package = Package(
    name: "ClipboardManager",
    platforms: [.macOS(.v13)],
    products: [ ... ],
    // Version is managed via Git tags
)
```

### Version History
See `CHANGELOG.md` for complete version history.

### Releasing a New Version

1. **Update version**
   ```bash
   # Edit Package.swift or Constants.swift
   git commit -m "chore: bump version to 1.1.0"
   ```

2. **Create release**
   ```bash
   git tag v1.1.0
   git push --tags
   ```

3. **Build and test**
   ```bash
   swift build -c release
   ./.build/release/ClipboardManager
   ```

4. **Publish**
   - Create GitHub release with binary
   - Update homebrew-tap (if applicable)
   - Announce on social media

## Troubleshooting

### Build fails with Swift version error
```
error: tools version requirement of 5.9 is not satisfied by the 5.8.0 installed tool
```

**Solution**: Update Xcode
```bash
# Install Xcode command line tools
xcode-select --install

# Or update Xcode from App Store
```

### Build fails with missing framework
```
error: unknown module 'ApplicationServices'
```

**Solution**: This is provided by macOS. Ensure target is set to macOS 13+

Check in `Package.swift`:
```swift
platforms: [
    .macOS(.v13)  // Minimum version
]
```

### Linting fails before release
```
swiftlint: 5 warning(s) found
```

**Solution**: Fix all warnings
```bash
swiftlint lint --strict  # See all warnings
# Fix each one, then:
swiftlint lint  # Should show 0 warnings
```

### Code signature issues on distribution
```
error: The binary is not signed
```

**Solution**: Sign the binary
```bash
codesign -s - .build/release/ClipboardManager
codesign -v .build/release/ClipboardManager  # Verify
```

## CI/CD Pipeline

Automated builds and tests on Git push:

See `.github/workflows/ci.yml` for configuration.

### What runs on every commit:
1. Code formatting check
2. SwiftLint validation
3. Swift build (debug)
4. Basic smoke tests

### What runs on release tag:
1. All above steps
2. Release build (optimized)
3. Code signing
4. Create GitHub release with binary

## Performance Tips for Distribution

### Optimize binary size
```bash
# Enabled by default in release builds
swift build -c release -Xswiftc -Osize
```

Typical sizes:
- Debug binary: 500 MB (includes debug info)
- Release binary: 50-80 MB

### Startup time optimization
Current startup time: ~100-200ms

To profile:
```bash
time ./.build/release/ClipboardManager
```

---

Related documentation:
- `SETUP.md` - Local development setup
- `SWIFT_CONVENTIONS.md` - Code style that affects buildability
- `DISTRIBUTION_GUIDE.md` - App Store and notarization details
