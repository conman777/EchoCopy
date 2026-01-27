#!/bin/bash
# Automated screenshot script for EchoCopy
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCREENSHOTS_DIR="$SCRIPT_DIR/screenshots"
mkdir -p "$SCREENSHOTS_DIR"

echo "🚀 Preparing to take new screenshots..."

# Ensure the app is running
open "$SCRIPT_DIR/dist/EchoCopy.app"
sleep 2

# 1. Capture Main Window
echo "📸 Capturing Main History Window..."
# Bring to front
osascript -e 'tell application "System Events" to tell process "EchoCopy" to set frontmost to true'
sleep 1
# Capture the front window of the process
WINDOW_ID=$(osascript -e 'tell edge to id of window 1' 2>/dev/null || echo "")
# Fallback to manual if automation fails, but try to find it by name/process
screencapture -x -R10,50,350,500 "$SCREENSHOTS_DIR/clipboard-history.png" 2>/dev/null || screencapture -w "$SCREENSHOTS_DIR/clipboard-history.png"

# 2. Capture Settings Window
echo "📸 Opening Settings..."
osascript -e 'tell application "System Events" to keystroke "," using command down'
sleep 2
echo "📸 Capturing Settings Window..."
# We will use manual capture for best results since settings windows can be tricky to target
echo "Please CLICK on the Settings window to capture it (or wait 5 seconds for auto-capture)..."
screencapture -x -w "$SCREENSHOTS_DIR/settings.png"

echo "✅ Screenshots updated in $SCREENSHOTS_DIR"
ls -lh "$SCREENSHOTS_DIR"