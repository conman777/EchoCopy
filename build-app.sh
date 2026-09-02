#!/bin/bash
set -euo pipefail

# Build a proper macOS app bundle

APP_NAME="EchoCopy"
DIST_DIR="${DIST_DIR:-dist}"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.app.zip"
BUNDLE_ID="${BUNDLE_ID:-com.yourcompany.echocopy}"
SOURCE_INFO_PLIST="Sources/EchoCopy/Info.plist"

bash scripts/verify-release-version.sh "${SOURCE_INFO_PLIST}"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${SOURCE_INFO_PLIST}")"
SOURCE_BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${SOURCE_INFO_PLIST}")"
VERSION="${VERSION:-${SOURCE_VERSION}}"
BUILD_NUMBER="${BUILD_NUMBER:-${SOURCE_BUILD_NUMBER}}"

if [[ "${VERSION}" != "${SOURCE_VERSION}" ]]; then
  echo "❌ VERSION=${VERSION} does not match ${SOURCE_INFO_PLIST} (${SOURCE_VERSION}). Update the source plist first." >&2
  exit 1
fi

if [[ "${BUILD_NUMBER}" != "${SOURCE_BUILD_NUMBER}" ]]; then
  echo "❌ BUILD_NUMBER=${BUILD_NUMBER} does not match ${SOURCE_INFO_PLIST} (${SOURCE_BUILD_NUMBER}). Update the source plist first." >&2
  exit 1
fi

find_default_signing_identity() {
  local identities prefix candidate

  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  # Prefer a development identity for local builds, then a Developer ID
  # identity. Fall back to any other valid code-signing identity.
  for prefix in "Apple Development:" "Developer ID Application:" "Mac Developer:"; do
    candidate="$(awk -F '"' -v prefix="${prefix}" \
      'index($2, prefix) == 1 { print $2; exit }' <<< "${identities}")"
    if [[ -n "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return
    fi
  done

  awk -F '"' \
    '$1 ~ /^[[:space:]]*[0-9]+\)/ && NF >= 3 { print $2; exit }' \
    <<< "${identities}"
}

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
  SIGNING_IDENTITY="$(find_default_signing_identity)"
fi

if [[ -z "${SIGNING_IDENTITY}" ]]; then
  echo "❌ No usable code-signing identity was found. Refusing to create an ad-hoc build that loses macOS permission continuity." >&2
  echo "   Install/unlock your certificate, or explicitly request a disposable build with SIGNING_IDENTITY=- ./build-app.sh" >&2
  exit 1
fi

# Never silently replace an already-authorized app with a different signing
# identity. macOS Accessibility and Keychain grants are bound to the signed
# identity, so doing that would make permissions appear to reset again.
if [[ -d "${APP_BUNDLE}" ]]; then
  previous_signing_identity="$(codesign -d -r- "${APP_BUNDLE}" 2>&1 \
    | sed -n 's/.*certificate leaf\[subject.CN\] = "\(.*\)".*/\1/p' \
    | head -n 1)"
  if [[ -n "${previous_signing_identity}" && "${previous_signing_identity}" != "${SIGNING_IDENTITY}" ]]; then
    echo "❌ Refusing to change EchoCopy's signing identity." >&2
    echo "   Existing: ${previous_signing_identity}" >&2
    echo "   Selected: ${SIGNING_IDENTITY}" >&2
    echo "   Set SIGNING_IDENTITY explicitly only when you intend a one-time macOS permission migration." >&2
    exit 1
  fi
fi

echo "🔨 Building ${APP_NAME} (release)..."
swift build -c release
BUILD_DIR="$(swift build --show-bin-path -c release)"

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
cp "${SOURCE_INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"

# Embed the canonical source metadata; mismatched environment overrides were
# rejected before the build started.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"
bash scripts/verify-release-version.sh "${CONTENTS_DIR}/Info.plist"

# Re-sign the assembled local bundle. SwiftPM signs the standalone executable,
# but that signature is no longer valid after it is placed inside an app bundle.
echo "🔏 Signing with: ${SIGNING_IDENTITY}"
codesign --force --deep --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  echo "ℹ️  This ad-hoc development signature changes after rebuilds; macOS may require manual permission reauthorization."
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
