#!/bin/bash
set -euo pipefail

# Build a proper macOS app bundle

APP_NAME="ClipboardManager"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.app.zip"

echo "🔨 Building ${APP_NAME} (release)..."
swift build -c release

echo "📦 Creating app bundle..."

# Remove old bundle if it exists
rm -rf "$APP_BUNDLE"
mkdir -p "$DIST_DIR"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "${CONTENTS_DIR}/Resources"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist (used when the bundle is launched via Finder)
cp "Sources/ClipboardManager/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Optional overrides
if [[ -n "${BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${CONTENTS_DIR}/Info.plist"
fi

if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS_DIR}/Info.plist" || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${CONTENTS_DIR}/Info.plist" || true
fi

# Create a portable zip for easy install/sharing
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "✅ App bundle created at: ${APP_BUNDLE}"
echo "✅ Zip created at: ${ZIP_PATH}"

if [[ "${1:-}" == "--open" ]]; then
  echo "🚀 Launching ${APP_NAME}..."
  open "${APP_BUNDLE}"
fi
