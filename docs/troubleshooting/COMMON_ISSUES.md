# Common Issues and FAQ

## Clipboard Monitoring Issues

### Clipboard items not being captured
**Problem**: App is running but items aren't being added to history

**Diagnosis**:
1. Check app is running: Look for ClipboardManager in menu bar
2. Try copying something simple (text) to test
3. Check the app log for error messages

**Solutions**:
- Restart the app: Quit from menu bar → Run again
- Some apps prevent clipboard access - try copying from a different app
- Accessibility permissions: System Preferences → Security → Accessibility → Add ClipboardManager

### Images/files not being captured
**Problem**: Only text items appear in history

**Status**: This is expected behavior
- **Images**: Supported - should appear as "[Image]" entries
- **Files**: File paths supported as text
- **Binary data**: Not supported

**If images not captured**:
- Check accessibility permissions
- Try using Cmd+C to copy an image from another app
- Some apps don't use standard clipboard APIs

### Duplicate items appearing
**Problem**: Same item appears multiple times

**Causes**:
1. Copying the same item twice (expected)
2. App copying item back to clipboard after paste (creates new change event)

**Note**: Consecutive identical items are deduplicated by design. If items appear multiple times with gaps, they were pasted separately.

## Popup Window Issues

### Option+V shortcut not working
**Problem**: Pressing Option+V doesn't show clipboard popup

**Diagnosis Steps**:
1. Check accessibility permissions: System Preferences → Security → Accessibility
2. Verify ClipboardManager is in the list and enabled
3. Try restarting the app

**Solutions**:
- Add ClipboardManager to accessibility list if missing
- Grant full accessibility permissions
- Restart macOS (rare, but sometimes helps with permissions)

### Popup appears at wrong location
**Problem**: Popup window appears in unexpected position

**Expected behavior**: Should appear near your cursor

**Workaround**: This is handled by the OS. If it's off-screen, try using the menu bar → Open ClipboardManager instead.

### Popup closes immediately after opening
**Problem**: Window opens and closes instantly

**Causes**:
1. Clicking outside popup immediately closes it (by design)
2. Another app steals focus

**Solutions**:
- Try the shortcut again slowly
- Close other floating windows
- Restart the app

## Search and History Issues

### Search not finding items
**Problem**: Items exist but search returns no results

**Checks**:
1. Search is case-insensitive - capitalization doesn't matter
2. Searches the full content (not just preview)
3. Partial matches work (e.g., searching "clip" finds "clipboard")

**Solutions**:
- Clear search and try again
- Manually scroll to verify item exists
- Check the item wasn't trimmed (500 item limit)

### History appearing empty on startup
**Problem**: App launches with no items shown

**Possible causes**:
1. History was cleared (Cmd+Shift+K clears it)
2. First run of app (no history yet)
3. History file corrupted

**Recovery**:
- Copy something new to populate history
- If history doesn't load, it may be corrupted - app will start fresh

## Performance Issues

### App using lots of memory
**Problem**: ClipboardManager consuming more RAM than expected

**Typical usage**: 30-80 MB (with 500 items in history)

**If higher**:
- Clear history: Cmd+Shift+K
- Quit and restart app
- Check for large images in clipboard history

### Clipboard monitor slow/laggy
**Problem**: App feels sluggish, clipboard monitoring lags

**Unlikely cause**: Monitoring is very efficient (polls every 500ms)

**More likely causes**:
- Other heavy apps running
- System disk full
- Recent macOS update

**Solutions**:
- Quit other apps
- Check system resources with Activity Monitor
- Restart macOS

## Keyboard Shortcut Issues

### Cmd+Shift+K not working to clear history
**Problem**: Clear history shortcut doesn't respond

**Causes**:
- Focus not on main app window
- Keyboard layout difference
- Shortcut conflict with another app

**Solutions**:
- Click on app window first to ensure focus
- Use menu bar: Click icon → Open ClipboardManager → Click "Clear All" button
- Check System Preferences → Keyboard → Shortcuts for conflicts

### Cmd+Alt+1-9 quick paste not working
**Problem**: Quick paste shortcuts don't paste items

**Status**: These require accessibility permissions

**Solution**:
- Grant accessibility permissions
- Ensure focus is in any text field
- Try Cmd+Alt+1 (should paste most recent item)

## Menu Bar Issues

### Menu bar icon not showing
**Problem**: No icon appears in macOS menu bar

**Causes**:
1. App not running
2. Menu bar full (rare)
3. Dock showing instead (app is hidden)

**Solutions**:
- Launch app: `swift run ClipboardManager`
- Restart app if already running
- Check menu bar (right side) for icon

### Menu items in menu bar not updating
**Problem**: Top 10 items in menu bar don't show recent additions

**Refresh timing**: Menu updates whenever history changes

**If stale**:
- Copy something new (forces update)
- Restart app

## Permission Issues

### "Accessibility permission required" message
**Problem**: App shows accessibility requirement dialog

**Solution**: Follow the prompt:
1. System Preferences opens
2. Go to Security & Privacy
3. Find ClipboardManager in Accessibility list
4. Enable it (may need to unlock the list)
5. Restart the app

### Copy/paste not working in some apps
**Problem**: Clipboard shortcuts work in some apps but not others

**Likely cause**: App uses non-standard clipboard implementation

**Workaround**:
1. Use the app's native copy/paste
2. Use ClipboardManager for text copying
3. Try using the main window instead of quick paste

## Window Management Issues

### Window not showing when clicking menu bar icon
**Problem**: Clicking the menu bar icon doesn't show the window

**Behavior**: Clicking icon should toggle window visibility

**Solutions**:
- App window might be minimized to dock - restore from dock
- Try using menu bar → "Open ClipboardManager"
- Restart the app

### Can't minimize app to dock
**Problem**: Minimize button is hidden/doesn't work

**By design**: This is a menu bar app that hides instead of minimizes
- Clicking the menu bar icon toggles visibility
- Closing the window hides it (doesn't quit app)
- Cmd+M hides the window
- Quit from menu or Cmd+Q to exit

## Storage Issues

### History lost after quit
**Problem**: Items disappear when restarting app

**Note**: History is saved and restored automatically

**If items missing**:
1. Check if you cleared history (Cmd+Shift+K)
2. Quit and restart app
3. Try copying something new

**Backup**: History is stored in `~/Library/Preferences/com.apple.nsuserdefaults.plist`

## Still Having Issues?

1. **Check logs**: Run in Terminal to see error messages
   ```bash
   swift run ClipboardManager 2>&1
   ```

2. **Look at architecture**: See `docs/architecture/SYSTEM_ARCHITECTURE.md` to understand how it works

3. **Try fresh install**:
   ```bash
   swift build -c release
   swift run ClipboardManager
   ```

For unresolved issues, check if there's a GitHub issue or create one with:
- Exact steps to reproduce
- What you expected to happen
- What actually happened
- macOS version and app version
