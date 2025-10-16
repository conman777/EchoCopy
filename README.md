# ClipboardManager

A simple, fast clipboard manager for macOS built with Swift and SwiftUI.

## Features

- **Clipboard History** - Automatically tracks everything you copy
- **Search** - Quickly find past clipboard items
- **Pin Items** - Mark frequently used snippets as favorites
- **Persistent Storage** - History is saved and restored on app restart
- **Keyboard Shortcuts** - Quick access to common actions
  - `Cmd+Shift+K` - Clear all history

## Building

### Requirements
- macOS 13 or later
- Swift 5.9+

### Build the project

```bash
cd ClipboardManager
swift build -c release
```

The compiled executable will be at: `.build/release/ClipboardManager`

## Running

### From command line:
```bash
swift run ClipboardManager
```

### Or run the compiled binary:
```bash
.build/release/ClipboardManager
```

## Usage

1. **Launch the app** - The window will open showing your clipboard history
2. **Copy anything** - The app automatically captures all text you copy
3. **Search** - Use the search bar to filter through history
4. **Click to paste** - Click the copy icon to paste an item to your clipboard
5. **Pin items** - Click the pin icon to mark important items

## Project Structure

```
ClipboardManager/
├── Package.swift           # Swift package configuration
├── README.md              # This file
└── Sources/
    └── ClipboardManager/
        └── App.swift      # All source code (consolidated)
```

## How it works

- **ClipboardMonitor** - Polls the system clipboard every 500ms for changes
- **ClipboardHistory** - Manages the in-memory and persistent history
- **ClipboardItem** - Data model for each clipboard entry
- **ContentView** - SwiftUI interface for browsing and managing items

## Keyboard Shortcuts

- `Cmd+Shift+K` - Clear all clipboard history

## Storage

Clipboard history is stored in UserDefaults under the key `clipboardHistory`. It persists between app launches up to 100 items.

## Limitations

- Currently only supports text clipboard items
- No menu bar integration yet (can be added as a future feature)
- Requires the app window to be open to monitor clipboard

## Future Enhancements

- Menu bar app with quick access
- Image clipboard support
- Cloud sync
- Multiple items search filter
- Custom keyboard shortcuts
- Clipboard statistics
