# ClipboardManager

A simple, fast clipboard manager for macOS built with Swift and SwiftUI.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Screenshots

<!-- Screenshots will be added here -->
*Screenshots coming soon - run `./take-screenshots.sh` to generate them*

## Features

- **Clipboard History** - Automatically tracks what you copy (text, URLs, images)
- **Search** - Quickly find past items
- **Pin Items** - Keep frequently used snippets at the top
- **Menu Bar App** - Lives in the macOS menu bar, no dock icon
- **Quick Popup** - `Option+V` opens a compact picker near your cursor
- **App Exclusions** - Prevent saving clipboard content from specific apps (e.g. password managers)
- **In-App Updates** - Check for updates directly from Settings
- **Persistent Storage** - History is saved and restored on app restart (up to 500 items)

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Option+V` | Show quick popup near cursor |
| `Cmd+Option+1-9` | Quick paste items 1-9 |
| `Cmd+Shift+K` | Clear all history |
| `Cmd+,` | Open Settings |

## Installation

### Download
Download the latest release from [GitHub Releases](https://github.com/conman777/copynoteapple/releases).

### Build from Source

**Requirements:**
- macOS 13 or later
- Swift 5.9+

```bash
# Clone the repo
git clone https://github.com/conman777/copynoteapple.git
cd copynoteapple

# Build the app bundle
./build-app.sh

# The app will be at dist/ClipboardManager.app
# Drag it to /Applications to install
```

To build and launch immediately:
```bash
./build-app.sh --open
```

## Usage

1. **Launch the app** - Click the clipboard icon in the menu bar
2. **Copy anything** - The app automatically captures text, URLs, and images
3. **Search** - Use the search bar to filter through history
4. **Click to paste** - Click any item to copy it back to clipboard
5. **Pin items** - Click the pin icon to keep important items at the top
6. **Quick access** - Press `Option+V` anywhere for a popup picker

## Permissions

The app requires:
- **Accessibility** - For global keyboard shortcuts (Option+V)
- You'll be prompted to grant this on first launch

## Settings

Access Settings via the menu bar icon (right-click) or `Cmd+,`:

- **Updates** - Check for new versions
- **Exclusions** - Add apps to exclude from clipboard tracking (e.g., 1Password, Bitwarden)

## Project Structure

```
ClipboardManager/
├── Package.swift              # Swift package configuration
├── build-app.sh              # Build script
├── Sources/
│   └── ClipboardManager/
│       ├── App.swift         # Main source code
│       └── Info.plist        # App metadata
└── dist/                     # Built app bundle
```

## How It Works

- **ClipboardMonitor** - Polls the system clipboard every 500ms for changes
- **ClipboardHistory** - Manages in-memory and persistent history
- **GlobalShortcutHandler** - Handles Option+V via CGEventTap
- **UpdateChecker** - Checks GitHub releases for updates

## Storage

Clipboard history is stored in UserDefaults. Data is stored locally on your machine.

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT
