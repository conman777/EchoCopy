# EchoCopy

<p align="center">
  <img src="https://img.icons8.com/fluency/200/clipboard.png" alt="EchoCopy Icon" width="128">
  <br>
  A modern, high-performance clipboard manager for macOS that prioritizes speed and visual clarity.
</p>

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-1.0.4-purple)

## Key Features

### 🖼️ High-Visibility Previews
Copy images or take screenshots and see them instantly. Standard macOS screenshot shortcuts automatically place the capture on the clipboard while retaining the normal screenshot file. Unlike other managers that show generic icons, EchoCopy provides large, clear previews so you know exactly what you're pasting.

<p align="center">
  <img src="screenshots/preview-new.png" alt="Clipboard History Previews" width="500">
</p>

### ⚡ Quick HUD Picker (Control+V or Cmd+Shift+V)
Press `Control+V or Cmd+Shift+V` to open a Spotlight-style quick picker directly at your cursor. Use `Cmd+Option+1-9` to paste a recent item directly from history.

### 🔍 Instant Search & Pinning
Filter through hundreds of items instantly with the built-in search. Keep your most important snippets—like code blocks, terminal commands, or email templates—at the top by pinning them.

### 🛡️ Privacy & Exclusions
Automatically ignore data copied from sensitive apps like 1Password, Bitwarden, or Keychain. You can easily add any app to the exclusion list in Settings.

<p align="center">
  <img src="screenshots/settings-new.png" alt="Settings and Exclusions" width="500">
</p>

### 🚀 Safe Update Checks
The Settings menu checks the official GitHub release feed. Updates are opened on the official release page for manual download and installation; verify the notarized artifact before opening it.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Control+V or Cmd+Shift+V` | Show quick HUD picker near cursor |
| `Cmd+Option+1-9` | Quick paste items 1-9 from history |
| `Shift+Cmd+3`, `Shift+Cmd+4`, or `Shift+Cmd+6` | Save a screenshot and copy it to the clipboard |
| `Cmd+Shift+K` | Clear all history |
| `Cmd+,` | Open Settings |

EchoCopy runs as a menu-bar app rather than a Dock app. Click its clipboard icon in the macOS menu bar to open the menu, then choose **Open EchoCopy** for the history window. It intentionally does not add a separate application menu or Dock icon.

## Installation

### Download
Download the latest version from [GitHub Releases](https://github.com/conman777/EchoCopy/releases).

### Build from Source

```bash
# Clone and build
git clone https://github.com/conman777/EchoCopy.git
cd EchoCopy
./build-app.sh --open
```

Use `./run.sh` for subsequent local launches. It always opens the signed app bundle; launching `.build/release/EchoCopy` directly creates a separate SwiftPM identity and can make macOS permissions appear to reset.

## Privacy & Permissions

The global `Control+V`, `Cmd+Shift+V`, and automatic screenshot shortcuts use the Accessibility permission managed in **System Settings → Privacy & Security → Accessibility**. EchoCopy checks that permission silently and never opens the authorization prompt automatically. Automatic screenshot copying creates the saved screenshot file directly and does not scan or read your Desktop folder, so it does not request Desktop-folder access. Clipboard history is encrypted locally with AES-GCM using a key protected by the macOS Keychain, bounded to prevent oversized persistence, and never transmitted over the network. Password-manager and macOS Keychain/Passwords pasteboards are excluded by default; add other apps in Settings.

For development builds, `build-app.sh` automatically selects an installed Apple Development or Developer ID certificate so Accessibility and Keychain grants survive rebuilds. It refuses to silently fall back to an ad-hoc signature; use `SIGNING_IDENTITY=- ./build-app.sh` only when you intentionally want a disposable build whose macOS permissions may need to be granted again.

## License

MIT
