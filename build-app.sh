#!/bin/bash

# Build a proper macOS app bundle

echo "🔨 Building ClipboardManager as macOS app bundle..."

# Build the executable
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# Create the app bundle structure
APP_NAME="ClipboardManager"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "📦 Creating app bundle structure..."

# Remove old bundle if it exists
rm -rf "$APP_BUNDLE"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "${CONTENTS_DIR}/Resources"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "$MACOS_DIR/"

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ClipboardManager</string>
    <key>CFBundleIdentifier</key>
    <string>com.clipboard.manager</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ClipboardManager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ App bundle created at: $APP_BUNDLE"
echo "🚀 Launching ClipboardManager..."

# Launch the app
open "$APP_BUNDLE"
