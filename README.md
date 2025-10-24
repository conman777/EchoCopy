# ClipboardManager

A lightweight, privacy-focused clipboard history manager for macOS built with Swift and SwiftUI.

## Screenshots

> **Note**: See [`docs/SCREENSHOTS.md`](docs/SCREENSHOTS.md) for instructions on capturing these screenshots

### Menu Bar Integration
![Menu Bar](assets/images/screenshots/menu-bar.png)
*ClipboardManager lives in your menu bar for quick access*

### Quick Popup (Option+V)
![Popup Window](assets/images/screenshots/popup-window.png)
*Press Option+V anywhere to access recent clipboard items instantly*

### Main Window
![Main Window](assets/images/screenshots/main-window.png)
*Full clipboard history with search and pin functionality*

### Search Functionality
![Search](assets/images/screenshots/search.png)
*Quickly filter through your clipboard history*

### Pinned Items
![Pinned Items](assets/images/screenshots/pinned-items.png)
*Pin frequently used items for easy access*

## Features

- **Menu Bar Integration** - Lives in your menu bar with quick access
- **Quick Popup Window** - Press `Option+V` anywhere to see recent items
- **Clipboard History** - Automatically tracks up to 500 clipboard items
- **Search** - Quickly find past clipboard items with real-time filtering
- **Pin Items** - Mark frequently used snippets as favorites
- **Persistent Storage** - History is saved and restored on app restart
- **Global Keyboard Shortcuts** - Access clipboard from anywhere
  - `Option+V` - Show quick popup window
  - `Cmd+Alt+1-9` - Paste 1st through 9th most recent items
  - `Cmd+Shift+K` - Clear all history (when app is focused)
- **Privacy-Focused** - No network access, all data stored locally

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

### First Launch
1. **Launch the app** - A menu bar icon will appear at the top-right of your screen
2. **Grant Permissions** - Enable Accessibility permissions for global shortcuts
   - System Preferences → Security & Privacy → Accessibility
   - Add ClipboardManager to the list
3. **Start Copying** - The app automatically captures all text you copy

### Quick Access (Recommended)
1. **Press `Option+V`** - Shows popup window with recent items near your cursor
2. **Click any item** - Instantly pastes it to your current location
3. **Close automatically** - Popup closes after pasting or clicking outside

### Main Window
1. **Click menu bar icon** - Opens full clipboard history window
2. **Search** - Use the search bar to filter through history
3. **Click to copy** - Click any item to copy it to your clipboard
4. **Pin items** - Click the pin icon to mark important items for quick access
5. **Delete items** - Hover over items to reveal delete button

### Global Shortcuts
- `Option+V` - Show quick popup window (works anywhere)
- `Cmd+Alt+1-9` - Paste 1st through 9th item directly (works anywhere)
- `Cmd+Shift+K` - Clear all history (when app window is focused)

## Project Structure

```
ClipboardManager/
├── Package.swift                  # Swift package configuration
├── README.md                      # This file
├── CLAUDE.md                      # Development best practices
├── assets/
│   └── images/
│       └── screenshots/           # App screenshots for documentation
├── docs/
│   ├── architecture/
│   │   └── SYSTEM_ARCHITECTURE.md # System design and architecture
│   ├── development/
│   │   ├── SETUP.md              # Development environment setup
│   │   ├── SWIFT_CONVENTIONS.md  # Code style guidelines
│   │   └── BUILD_AND_DEPLOY.md   # Build and deployment guide
│   ├── features/
│   │   └── KEYBOARD_SHORTCUTS.md # Detailed keyboard shortcuts reference
│   └── troubleshooting/
│       └── COMMON_ISSUES.md      # FAQ and troubleshooting
└── Sources/
    └── ClipboardManager/
        ├── App.swift             # Main app entry point
        ├── AppDelegate.swift     # App lifecycle management
        ├── Models/
        │   ├── ClipboardItem.swift      # Data model for clipboard entries
        │   ├── ClipboardHistory.swift   # History management
        │   └── ContentType.swift        # Content type definitions
        ├── Services/
        │   ├── ClipboardMonitor.swift   # Clipboard monitoring service
        │   └── GlobalShortcutHandler.swift # Global keyboard shortcuts
        ├── AppKit/
        │   ├── MenuBarManager.swift     # Menu bar integration
        │   ├── MenuBarWindow.swift      # Custom window for menu bar
        │   ├── MenuBarWindowDelegate.swift # Window delegate
        │   └── PopupWindowManager.swift # Popup window management
        ├── Views/
        │   ├── ContentView.swift        # Main clipboard history view
        │   ├── ClipboardItemRow.swift   # Individual clipboard item UI
        │   ├── PopupView.swift          # Quick popup view
        │   └── PopupItemRow.swift       # Popup item UI
        ├── Utilities/
        │   ├── Constants.swift          # App constants
        │   ├── Extensions.swift         # Swift extensions
        │   └── WindowAccessor.swift     # Window utility helpers
        └── Info.plist           # App metadata
```

## How it works

- **ClipboardMonitor** - Polls the system clipboard every 500ms for changes
- **ClipboardHistory** - Manages the in-memory and persistent history (up to 500 items)
- **ClipboardItem** - Data model for each clipboard entry with content type detection
- **MenuBarManager** - Handles menu bar icon and window presentation
- **PopupWindowManager** - Manages the quick-access popup window
- **GlobalShortcutHandler** - Registers and handles global keyboard shortcuts
- **ContentView** - SwiftUI interface for browsing and managing items
- **PopupView** - SwiftUI interface for quick popup access

## Storage

Clipboard history is stored in UserDefaults under the key `clipboardHistory`. It persists between app launches up to 500 items.

## Current Limitations

- Currently only supports text clipboard items (images planned for future)
- Global shortcuts require Accessibility permissions
- Monitors clipboard changes every 500ms (not real-time)

## Future Enhancements

- Image clipboard support
- File path clipboard support
- Cloud sync between devices
- Clipboard statistics and usage analytics
- Custom keyboard shortcut configuration
- Multiple clipboard collections/categories
- Export/import clipboard history
