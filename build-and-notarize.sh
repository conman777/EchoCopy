#!/bin/bash
set -euo pipefail

echo "🏗️  Building EchoCopy for distribution..."

# Configuration can be provided through the environment. Keep the existing
# bundle identifier for upgrades so preferences and macOS permissions carry over.
DEVELOPER_ID="${DEVELOPER_ID:-}"
BUNDLE_ID="${BUNDLE_ID:-com.yourcompany.echocopy}"
APP_NAME="EchoCopy"
VERSION="${VERSION:-1.0.4}"

APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

if [[ -z "$DEVELOPER_ID" || "$DEVELOPER_ID" == *"Your Name"* || "$DEVELOPER_ID" == *"TEAM_ID"* ]]; then
  echo "Set DEVELOPER_ID to an installed Developer ID Application certificate before creating a release." >&2
  exit 1
fi

if [[ "$BUNDLE_ID" != *.* ]]; then
  echo "BUNDLE_ID must be a stable reverse-DNS identifier." >&2
  exit 1
fi

if [[ "$BUNDLE_ID" != "com.yourcompany.echocopy" ]]; then
  echo "Warning: changing the existing bundle identifier creates a new macOS permission and preferences identity." >&2
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$APP_BUNDLE"
rm -f "$DMG_NAME"
swift package clean

# Build with Swift Package Manager
echo "🔨 Building with SPM..."
swift build -c release --arch arm64 --arch x86_64
BUILD_DIR="$(swift build --show-bin-path -c release --arch arm64 --arch x86_64)"

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/EchoCopy" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
cp "Sources/EchoCopy/Info.plist" "${APP_BUNDLE}/Contents/"

# Update Info.plist with release values
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "${APP_BUNDLE}/Contents/Info.plist"

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
