#!/bin/bash
set -euo pipefail

# Always launch the signed app bundle. Running .build/release/EchoCopy directly
# creates a new ad-hoc/SwiftPM identity and makes macOS Accessibility and
# Keychain permissions appear to reset on every rebuild.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/build-app.sh" --open
