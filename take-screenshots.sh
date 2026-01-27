#!/bin/bash
# Screenshot script for ClipboardManager
# Run this after granting Screen Recording permission to Terminal

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCREENSHOTS_DIR="$SCRIPT_DIR/screenshots"

mkdir -p "$SCREENSHOTS_DIR"

echo "Taking screenshots for ClipboardManager..."

# Clear app preferences to get fresh demo data
defaults delete com.yourcompany.clipboardmanager 2>/dev/null || true

# Launch the app with demo data
open "$SCRIPT_DIR/dist/ClipboardManager.app" --args --demo-data
sleep 2

# Click on menu bar to open main window
osascript -e '
tell application "System Events"
    tell process "ClipboardManager"
        click menu bar item 1 of menu bar 2
    end tell
end tell
'
sleep 1

# Capture the main window
echo "Please click on the ClipboardManager window to capture it..."
screencapture -w "$SCREENSHOTS_DIR/main-window.png"
echo "Main window captured!"

# Show Option+V popup
echo "Press Option+V to show the popup, then click to capture it..."
screencapture -w "$SCREENSHOTS_DIR/popup.png"
echo "Popup captured!"

# Open settings and capture
osascript -e '
tell application "System Events"
    tell process "ClipboardManager"
        click menu bar item 1 of menu bar 2
    end tell
end tell
'
sleep 0.5
osascript -e '
tell application "System Events"
    keystroke "," using command down
end tell
'
sleep 1
echo "Click on the Settings window to capture it..."
screencapture -w "$SCREENSHOTS_DIR/settings.png"
echo "Settings captured!"

echo ""
echo "Screenshots saved to: $SCREENSHOTS_DIR"
ls -la "$SCREENSHOTS_DIR"

echo ""
echo "Now run: git add screenshots/ && git commit -m 'docs: add app screenshots' && git push"
