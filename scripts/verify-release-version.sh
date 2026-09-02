#!/bin/bash
set -euo pipefail

PLIST_PATH="${1:-Sources/EchoCopy/Info.plist}"
RELEASE_TAG="${2:-}"

if [[ ! -f "${PLIST_PATH}" ]]; then
  echo "Version check failed: plist not found at ${PLIST_PATH}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST_PATH}")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST_PATH}")"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version check failed: ${VERSION} is not a numeric major.minor.patch version." >&2
  exit 1
fi

if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "Version check failed: build number ${BUILD_NUMBER} is not numeric." >&2
  exit 1
fi

if [[ -n "${RELEASE_TAG}" ]]; then
  TAG_VERSION="${RELEASE_TAG#v}"
  TAG_VERSION="${TAG_VERSION#V}"
  if [[ "${TAG_VERSION}" != "${VERSION}" ]]; then
    echo "Version check failed: release tag ${RELEASE_TAG} does not match bundle version ${VERSION}." >&2
    exit 1
  fi
fi

echo "✅ Version metadata verified: ${VERSION} (build ${BUILD_NUMBER})${RELEASE_TAG:+ for ${RELEASE_TAG}}"
