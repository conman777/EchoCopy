# EchoCopy

<p align="center">
  <img src="https://img.icons8.com/fluency/200/clipboard.png" alt="EchoCopy Icon" width="128">
  <br>
  A modern, high-performance clipboard manager for macOS that prioritizes speed and visual clarity.
</p>

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-1.0.7-purple)

## Key Features

### 🖼️ Clear Image Previews
Copy images and see compact visual previews alongside the rest of your history. Optional screenshot capture can also add standard macOS screenshots to EchoCopy while retaining the normal screenshot file.

<p align="center">
  <img src="screenshots/preview-new.png" alt="Clipboard History Previews" width="500">
</p>

### ⚡ One-Click Menu History
Click the EchoCopy menu-bar icon to see up to ten history rows at a time. Scroll the compact list to reach older items, then choose one to paste it into the app you were using. Open the full EchoCopy window when you want to search or manage pinned items.

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
| `Shift+Cmd+3` or `Shift+Cmd+4` | Optionally add screenshots to EchoCopy |
| `Cmd+Shift+K` | Clear all history |
| `Cmd+,` | Open Settings |

EchoCopy runs as a menu-bar app rather than a Dock app. Click its clipboard icon in the macOS menu bar to open a ten-row scrolling history panel, then click an item to paste. Choose **Open EchoCopy** for the searchable history window. EchoCopy intentionally does not add a separate application menu or Dock icon.

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

The one-click paste action and optional screenshot capture use the Accessibility permission managed in **System Settings → Privacy & Security → Accessibility**. EchoCopy checks that permission silently and never opens the authorization prompt automatically. Optional screenshot copying creates the saved screenshot file directly and does not scan or read your Desktop folder, so it does not request Desktop-folder access. Clipboard history is encrypted locally with AES-GCM using a key protected by the macOS Keychain, bounded to prevent oversized persistence, and never transmitted over the network. Password-manager and macOS Keychain/Passwords pasteboards are excluded by default; add other apps in Settings.

For development builds, `build-app.sh` automatically selects an installed Apple Development or Developer ID certificate so Accessibility and Keychain grants survive rebuilds. It refuses to silently fall back to an ad-hoc signature; use `SIGNING_IDENTITY=- ./build-app.sh` only when you intentionally want a disposable build whose macOS permissions may need to be granted again.

## License

MIT
