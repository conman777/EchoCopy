# Keyboard Shortcuts

## Global Shortcuts (Work Anywhere)

### Option+V - Show Clipboard Popup
Shows a quick-access popup window with your recent clipboard items

**When it works**: When the app is running and you have accessibility permissions
**What it does**:
- Shows popup near your cursor with 10 most recent items
- Click any item to paste it immediately
- Popup closes automatically after paste or when clicking outside

**Requirements**:
- System Preferences → Security & Privacy → Accessibility
- ClipboardManager must be enabled

**Tip**: Much faster than switching to the app window for quick pastes

### Cmd+Alt+1-9 - Quick Paste Items 1-9
Pastes the Nth most recent item directly to your cursor location

**Example**:
- Cmd+Alt+1 = Paste most recent item
- Cmd+Alt+2 = Paste 2nd most recent item
- Cmd+Alt+9 = Paste 9th most recent item

**When it works**: When the app is running and you have accessibility permissions
**Requirements**: Same as Option+V - needs accessibility permission

**Use case**: Developers who frequently switch between multiple snippets

## App Window Shortcuts (When App is Focused)

### Cmd+Shift+K - Clear All History
Permanently clears all clipboard history

**Confirmation**: App will ask "Are you sure?" (no confirmation - just clears)
**Recovery**: Cannot be undone - deleted items are permanently gone
**Tip**: Run this before sharing your computer

### Cmd+M - Hide Window
Hides the ClipboardManager window (equivalent to clicking menu bar icon)

**Behavior**:
- Window is hidden, not closed
- App continues running in background
- Menu bar icon remains visible
- Click menu bar icon to show window again

**Keyboard equivalent**: Cmd+M works anywhere in the window

## Search Shortcuts

### Cmd+F - Focus Search
*Not implemented yet* - Click search box to focus

**Workaround**: Click in the search field to start typing

### Esc - Clear Search
Clear the search field and show all items

**Behavior**: Pressing Esc while in search field clears it instantly

## System Shortcuts (macOS)

These are standard macOS shortcuts that work in ClipboardManager like any app:

### Cmd+C - Copy
Copies selected text in the app

### Cmd+V - Paste
Pastes from your current clipboard

### Cmd+Q - Quit
Closes the app completely

**Note**: ClipboardManager also runs as a menu bar app, so use the menu to quit

### Cmd+H - Hide Other Apps
Standard macOS shortcut to hide other windows

## Customization

### Accessibility Permission Required
Global shortcuts (Option+V, Cmd+Alt+1-9) require accessibility permission:

1. System Preferences → Security & Privacy
2. Click "Accessibility" in left sidebar
3. Click the lock to unlock
4. Click the "+" button
5. Navigate to ClipboardManager and add it
6. Click the lock to lock settings

### Disabling Global Shortcuts
You can't disable individual shortcuts, but you can:
- Revoke accessibility permission (disables all global shortcuts)
- Restart the app without the permission
- Continue using the app window (Cmd+Shift+K still works)

## Troubleshooting

### Option+V not working
**Problem**: Popup doesn't appear when pressing Option+V

**Diagnosis**:
1. Is ClipboardManager running? (Check menu bar)
2. Do you have accessibility permission? (System Preferences → Accessibility)
3. Is the app currently showing an alert? (Might block shortcuts)

**Solutions**:
- Grant accessibility permission and restart app
- Try restarting macOS
- Try restarting the app

### Cmd+Alt shortcuts conflicting with other apps
**Problem**: Cmd+Alt+Number does something else

**Causes**:
- Another app has same shortcut registered
- Accessibility permission not granted
- Focus on a non-text-field (shortcuts only work when appropriate)

**Solutions**:
- Check System Preferences → Keyboard → Shortcuts for conflicts
- Use Option+V popup instead for quick access
- Uncheck the conflicting shortcut in the other app

### Shortcuts stop working after system sleep
**Problem**: Option+V or Cmd+Alt shortcuts stop responding

**Causes**: Rare system hiccup with global event monitoring

**Solutions**:
- Click menu bar icon to bring up window manually
- Restart the app
- Restart macOS (rare, but sometimes needed)

## Related

- See `QUICK_POPUP.md` for Option+V popup details
- See `docs/development/SETUP.md` for permission setup
