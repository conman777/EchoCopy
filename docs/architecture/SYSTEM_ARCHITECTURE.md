# System Architecture

## Overview

ClipboardManager is a lightweight, efficient macOS menu bar application that monitors the system clipboard and maintains a searchable history of clipboard items. It's built with Swift and SwiftUI for modern macOS (13.0+).

## Core Philosophy

- **Single Responsibility**: Each component has a clear, focused purpose
- **Modular Structure**: Easy to test and extend without coupling
- **Minimal Overhead**: Efficient polling and storage to avoid system impact
- **User-Friendly**: Intuitive UI with keyboard shortcuts for power users

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    ClipboardManagerApp                       │
│                    (Entry Point)                            │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
    ┌───▼────────┐         ┌─────▼──────────┐
    │   Models    │         │  Services      │
    ├─────────────┤         ├────────────────┤
    │ ContentType │         │ ClipboardMon...│
    │ ClipboardI..│         │ Constants      │
    │ History     │         └────────────────┘
    └─────────────┘
        │
        ├─────────────────┬──────────────────┐
        │                 │                  │
    ┌───▼────────┐   ┌────▼────────┐   ┌───▼─────────┐
    │  Views      │   │  AppKit      │   │  Utilities  │
    ├─────────────┤   ├─────────────┤   ├─────────────┤
    │ ContentView │   │  AppDelegate │   │ WindowAcce..│
    │ ItemRow     │   │  MenuBar...  │   │ Extensions  │
    │ PopupView   │   │  GlobalShor..│   └─────────────┘
    └─────────────┘   │  PopupWindow...│
                      └────────────────┘
```

## Module Breakdown

### Models (Data Layer)
Location: `Sources/ClipboardManager/Models/`

**Purpose**: Define the data structures for clipboard history

- **ContentType.swift** - Enum for content types (text, image, file, url)
- **ClipboardItem.swift** - Individual clipboard entry with metadata (ID, timestamp, content type, pinned status)
- **ClipboardHistory.swift** - Observable collection managing all history items, persistence, and business logic

**Key Features**:
- Automatic duplicate detection
- Efficient trimming to max items (500)
- Proper error handling for save/load operations
- Input validation to prevent empty items

### Services (Business Logic)
Location: `Sources/ClipboardManager/Services/`

**Purpose**: Core functionality separate from UI

- **ClipboardMonitor.swift** - System clipboard monitoring with change detection
  - Polls every 500ms (configurable via Constants)
  - Handles multiple content types (text, image, URL, RTF)
  - Efficient change detection using NSPasteboard.changeCount

### Views (UI Layer)
Location: `Sources/ClipboardManager/Views/`

**Purpose**: All SwiftUI user interface components

- **ContentView.swift** - Main window with history list and search
- **ClipboardItemRow.swift** - Individual item display with actions
- **PopupView.swift** - Quick access popup (Option+V)
- **PopupItemRow.swift** - Compact item display in popup

### AppKit Integration (System Integration)
Location: `Sources/ClipboardManager/AppKit/`

**Purpose**: macOS-specific functionality

- **AppDelegate.swift** - Application lifecycle and window management
- **MenuBarManager.swift** - Status bar icon and quick menu
- **GlobalShortcutHandler.swift** - Global keyboard shortcuts (Option+V, Cmd+Alt+1-9)
- **PopupWindowManager.swift** - Manages Option+V popup lifecycle
- **MenuBarWindow.swift** - Custom window to intercept minimize behavior
- **MenuBarWindowDelegate.swift** - Window delegate for hide-instead-of-close behavior

### Utilities
Location: `Sources/ClipboardManager/Utilities/`

**Purpose**: Reusable code and configuration

- **Constants.swift** - Application-wide constants (max items, polling interval, etc.)
- **Extensions.swift** - View extensions (borderTop)
- **WindowAccessor.swift** - NSView representable for accessing underlying NSWindow

## Data Flow

### Clipboard Monitoring → History

```
System Clipboard
        │
        ▼ (polls every 500ms)
ClipboardMonitor.checkClipboard()
        │
        ├─ Detect change via NSPasteboard.changeCount
        │
        ├─ Check type priority: URL → Image → Text+RTF
        │
        ▼ Extract content and metadata
        │
        ▼ Validate (not empty, not duplicate)
        │
        ▼ ClipboardHistory.addItem()
        │
        ├─ Check for duplicates
        │
        ├─ Insert at front of @Published items array
        │
        ├─ Trim to maxItems (500)
        │
        ▼ Save to UserDefaults
        │
        ▼ SwiftUI @Published triggers view update
        │
        ▼ UI displays new item
```

### User Pastes from History

```
User clicks paste button in UI
        │
        ├─ ClipboardItemRow.pasteItem()
        │
        ▼ Determine content type
        │
        ├─ Text/URL: Set string + optional RTF
        ├─ Image: Decode base64 to NSImage
        └─ File: Set string path
        │
        ▼ NSPasteboard.general.setString/writeObjects
        │
        ▼ Clear previously, set new content
        │
        ▼ System clipboard now has new content
        │
        ▼ ClipboardMonitor detects change (via changeCount)
        │
        ▼ Adds as duplicate (skipped by duplicate check)
```

## Storage Architecture

### UserDefaults Storage

**Key**: `clipboardHistory`
**Value**: JSON-encoded array of ClipboardItem

**Benefits**:
- No database setup required
- Automatic synchronization across app instances
- Secure by default (sandbox permissions)
- Fast enough for 500 items

**Limitations**:
- 500-item limit (hard limit to prevent UserDefaults bloat)
- History lost on app uninstall
- No encryption (use MacOS keychain for sensitive data)

### Memory Model

- All items kept in memory (`@Published var items: [ClipboardItem]`)
- SwiftUI @Published triggers efficient UI updates
- Filtered items computed on-demand (no caching)

## Threading Model

- **Main Thread**: All UI updates, window management
- **Global Monitor Dispatch**: Global keyboard events (system-provided)
- **Timer-based Polling**: ClipboardMonitor timer runs on main thread
  - Safe because clipboard access is synchronous
  - Efficient at 500ms interval

## Security Considerations

1. **No System Access Required** - Uses standard macOS APIs
2. **Accessibility Permission** - Required for global keyboard shortcuts (Option+V)
3. **Sandboxing** - Can run in sandbox if needed (not currently bundled for sandbox)
4. **Clipboard Access** - Direct read-only access to system clipboard
5. **Data Protection** - History stored in UserDefaults (user-readable, not encrypted)

## Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| Clipboard check | <1ms | Simple changeCount comparison |
| Add item | 1-5ms | JSON encoding + UserDefaults save |
| Search 500 items | <1ms | Case-insensitive contains match |
| Load history | 5-20ms | JSON decode on app startup |
| UI update | 16-33ms | SwiftUI efficient rendering |

## Extension Points

The modular architecture makes these extensions easy:

- **New content types**: Add to ContentType enum and content handlers in ClipboardMonitor
- **Additional keyboard shortcuts**: GlobalShortcutHandler.handleGlobalKeyEvent()
- **Different storage**: Replace ClipboardHistory persistence methods
- **Cloud sync**: Add periodic sync to web service
- **Advanced search**: Enhance filtering in ContentView
- **Clipboard statistics**: Track frequency, time-of-day usage

## Dependencies

**Swift Standard Library**:
- Foundation (Date, UUID, JSON encoding)
- AppKit (NSPasteboard, NSWindow, NSEvent)
- SwiftUI (UI framework)
- Combine (Reactive)

**No external dependencies** - Pure Apple frameworks for reliability and security

## Build Targets

- **macOS 13.0+** - Minimum deployment target
- **Apple Silicon (arm64)** - Primary support
- **Intel (x86_64)** - Supported via universal binary
- **Swift 5.9+** - Language version requirement
