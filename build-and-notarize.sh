#!/bin/bash
set -e

echo "🏗️  Building Clipboard Manager for distribution..."

# Configuration - UPDATE THESE WITH YOUR ACTUAL VALUES
DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)"
BUNDLE_ID="com.yourcompany.clipboardmanager"
APP_NAME="EchoCopy"
VERSION="1.0.4"

# Build paths
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$BUILD_DIR"
rm -rf "$APP_BUNDLE"
rm -f "$DMG_NAME"

# Build with Swift Package Manager
echo "🔨 Building with SPM..."
swift build -c release --arch arm64 --arch x86_64

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/EchoCopy" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
cp "Sources/EchoCopy/Info.plist" "${APP_BUNDLE}/Contents/"

# Update Info.plist with actual values
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "${APP_BUNDLE}/Contents/Info.plist"

# Code sign with hardened runtime
echo "✍️  Code signing..."
codesign --force --options runtime \
  --entitlements EchoCopy.entitlements \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "${APP_BUNDLE}/Contents/MacOS/EchoCopy"

codesign --force --options runtime \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "${APP_BUNDLE}"

# Verify code signature
echo "🔍 Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# Create DMG for distribution
echo "💿 Creating DMG..."
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$APP_BUNDLE" \
  -ov -format UDZO \
  "$DMG_NAME"

# Sign the DMG
echo "✍️  Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" \
  --timestamp \
  "$DMG_NAME"

echo "✅ Build complete: $DMG_NAME"
echo ""
echo "📤 Next steps:"
echo "1. Notarize the DMG:"
echo "   xcrun notarytool submit $DMG_NAME --apple-id YOUR_APPLE_ID --team-id TEAM_ID --password APP_SPECIFIC_PASSWORD --wait"
echo ""
echo "2. Staple the notarization:"
echo "   xcrun stapler staple $DMG_NAME"
echo ""
echo "3. Verify notarization:"
echo "   spctl -a -vv -t install $DMG_NAME"
