# Screenshot Guide

This guide helps you capture high-quality screenshots of ClipboardManager for the README and documentation.

## Required Screenshots

### 1. Menu Bar Integration (`menu-bar.png`)

**What to capture**: The menu bar icon and dropdown menu

**Steps**:
1. Ensure ClipboardManager is running
2. Look for the clipboard icon in the menu bar (top-right of screen)
3. Click the icon to open the menu
4. Take screenshot: `Cmd+Shift+4`, then press `Space`, click on the menu

**Save to**: `assets/images/screenshots/menu-bar.png`

**Tips**:
- Make sure your menu bar isn't too cluttered
- Capture just the dropdown menu and surrounding menu bar icons
- Use light mode for better visibility

---

### 2. Quick Popup Window (`popup-window.png`)

**What to capture**: The Option+V popup window showing recent items

**Steps**:
1. Ensure ClipboardManager is running
2. Copy a few different text items to build up clipboard history
3. Press `Option+V` to show the popup
4. Position the popup in a clean area of your screen
5. Take screenshot: `Cmd+Shift+4`, select area around popup

**Save to**: `assets/images/screenshots/popup-window.png`

**Tips**:
- Make sure you have at least 5-6 items in the popup for a good visual
- Capture the popup with some background for context
- Show the cursor hovering over an item to demonstrate interactivity
- Use a clean desktop background

---

### 3. Main Window (`main-window.png`)

**What to capture**: Full clipboard history window with multiple items

**Steps**:
1. Click the menu bar icon to open the main window
2. Ensure you have diverse clipboard items (text of various lengths)
3. Make sure window is at a good size (not too small, not full screen)
4. Take screenshot: `Cmd+Shift+4` and select the entire window
   OR `Cmd+Shift+4`, press `Space`, click on the window (for drop shadow)

**Save to**: `assets/images/screenshots/main-window.png`

**Tips**:
- Have 10-15 visible items for demonstration
- Mix short and long text items
- Include at least one pinned item (with pin icon visible)
- Make sure the search bar is visible at the top
- Window should be large enough to show multiple items clearly

---

### 4. Search Functionality (`search.png`)

**What to capture**: Main window with active search showing filtered results

**Steps**:
1. Open the main ClipboardManager window
2. Click in the search bar at the top
3. Type a search term that filters your clipboard items
4. Ensure filtered results are visible
5. Take screenshot: `Cmd+Shift+4`, select entire window

**Save to**: `assets/images/screenshots/search.png`

**Tips**:
- Use a search term that returns 3-5 results (not too many, not too few)
- Make sure the search bar shows your search term clearly
- Highlight matching text in results if possible
- Show that some items are filtered out

---

### 5. Pinned Items (`pinned-items.png`)

**What to capture**: Main window highlighting pinned items feature

**Steps**:
1. Open the main ClipboardManager window
2. Pin 2-3 items by clicking the pin icon
3. Ensure pinned items are visible (they should appear at the top or have pin icon)
4. Hover over a pinned item to show the unpin option (if applicable)
5. Take screenshot: `Cmd+Shift+4`, select entire window

**Save to**: `assets/images/screenshots/pinned-items.png`

**Tips**:
- Have a mix of pinned and unpinned items
- Pinned items should be clearly distinguishable
- Show the pin icon prominently
- Consider highlighting a pinned item by hovering over it

---

## Screenshot Best Practices

### macOS Screenshot Tools

**Region Selection**: `Cmd+Shift+4`
- Cursor becomes crosshair
- Click and drag to select area
- Screenshot saves to Desktop by default

**Window Capture**: `Cmd+Shift+4`, then press `Space`
- Cursor becomes camera icon
- Click on any window to capture it
- Automatically includes drop shadow
- Great for full window shots

**Clipboard Capture**: `Cmd+Shift+Control+4`
- Same as above but copies to clipboard instead of saving file
- Useful for quick editing

### Tips for High-Quality Screenshots

1. **Resolution**: Use Retina display if available for crisp screenshots
2. **Lighting**: Use light mode for better visibility in documentation
3. **Clean Background**: Close unnecessary windows and apps
4. **Consistent Styling**: Use the same macOS theme (light/dark) for all screenshots
5. **File Format**: PNG is preferred for screenshots (default on macOS)
6. **File Size**: Keep images under 1MB for faster loading (compress if needed)

### After Taking Screenshots

1. **Review**: Check that all important elements are visible and clear
2. **Crop**: Remove unnecessary margins or UI elements
3. **Resize**: Ensure images aren't too large (max width ~1000px recommended)
4. **Rename**: Use the exact filenames specified above
5. **Move**: Place files in `assets/images/screenshots/` directory

### Optimizing Screenshots

You can compress screenshots without losing quality:

```bash
# Install ImageOptim (recommended)
brew install --cask imageoptim

# Or use built-in tools
sips -Z 1000 screenshot.png  # Resize to max 1000px width
```

---

## Quick Checklist

Before committing screenshots, verify:

- [ ] All 5 required screenshots captured
- [ ] Files named correctly (menu-bar.png, popup-window.png, etc.)
- [ ] Files saved to `assets/images/screenshots/`
- [ ] Images are clear and high resolution
- [ ] Consistent light/dark mode across all screenshots
- [ ] No sensitive information visible in clipboard content
- [ ] File sizes are reasonable (<1MB each)

---

## Example Content for Screenshots

Use these example clipboard items to populate your history:

```
function calculateTotal(items) {
  return items.reduce((sum, item) => sum + item.price, 0);
}

https://github.com/conman777/copynoteapple

brew install swift

const API_KEY = "demo-key-123"

git commit -m "feat: add clipboard history feature"

ClipboardManager is a lightweight macOS app

Option+V
```

Copy these one by one to build up a realistic clipboard history before taking screenshots.

---

## Need Help?

- Screenshots not saving? Check System Preferences → Keyboard → Screenshots
- Can't find saved screenshots? Check Desktop or Documents folder
- Need to change save location? Use `Cmd+Shift+5` for screenshot options
