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

### Screen Recordings to Clipboard
Enable **Copy completed screen recordings** in Settings → General. EchoCopy watches only the macOS Screenshot save folder for new `.mov` screen recordings, waits for a stable, playable file, and copies its file URL for pasting into apps that accept video attachments. Existing recordings are ignored. Detection uses macOS screen-capture metadata or the standard “Screen Recording” filename. Keep the original video file to paste it again from history; EchoCopy encrypts the history reference, not the video file. macOS may ask for access to the save folder. Saving elsewhere or renaming a recording before detection may prevent automatic copying.

### ⚡ One-Click Menu History
Click the EchoCopy menu-bar icon to see up to ten history rows at a time. Scroll the compact list to reach older items, then choose one to paste it into the app you were using. Open the full EchoCopy window when you want to search or manage pinned items.

### 🔍 Instant Search & Pinning
Filter through hundreds of items instantly with the built-in search. Keep your most important snippets—like code blocks, terminal commands, or email templates—at the top by pinning them.

### 🛡️ Privacy & Exclusions
Automatically ignore data copied from sensitive apps like 1Password, Bitwarden, or Keychain. You can easily add any app to the exclusion list in Settings.

<p align="center">
  <img src="screenshots/settings-new.png" alt="Settings and Exclusions" width="500">
</p>

In-app update checks are temporarily unavailable.

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

Opening either history view requires Touch ID. Closing history, switching away from EchoCopy, sleeping, or locking the Mac locks history again. Cancelling authentication leaves history hidden; a Mac with unavailable or locked-out Touch ID stays locked until Touch ID is available again. Existing history and background capture are preserved. This is an access lock on EchoCopy’s interface; the existing history encryption and system clipboard behavior are unchanged.

The one-click paste action uses the Accessibility permission managed in **System Settings → Privacy & Security → Accessibility**. EchoCopy checks that permission silently and never opens the authorization prompt automatically. Optional screenshot copying watches the configured Screenshot save folder for new images. Apple’s native floating preview remains available; EchoCopy reacts to folder changes and copies the image after macOS saves it, normally after the preview disappears or is dismissed. A brief readiness check avoids copying incomplete images; failed copies are retried. Folder access may be required. Clipboard history is encrypted locally with AES-GCM using a key protected by the macOS Keychain, bounded to prevent oversized persistence, and never transmitted over the network. Password-manager and macOS Keychain/Passwords pasteboards are excluded by default; add other apps in Settings.

History retains up to 500 items within a 256 MiB encrypted-payload budget (plus small encryption overhead). Oldest unpinned items are removed first when either limit is reached. Stored history up to 1 GiB still opens, so history saved under an earlier, larger budget is not locked out; it is trimmed to the current budget on the next save. History encryption covers text, images, rich text, filenames, timestamps, and pins. The history directory is restricted to the current user (0700), with its encrypted file at 0600; legacy plaintext is encrypted before file migration. The key is stored separately in Keychain. Encryption protects stored history, not the active macOS clipboard, the running app’s memory, or normal screenshot files exported to your Screenshot location. Existing files and OS backups are not encrypted or deleted by EchoCopy. Clearing active history also does not delete encrypted legacy recovery backups.

For development builds, `build-app.sh` automatically selects an installed Apple Development or Developer ID certificate so Accessibility and Keychain grants survive rebuilds. It refuses to silently fall back to an ad-hoc signature; use `SIGNING_IDENTITY=- ./build-app.sh` only when you intentionally want a disposable build whose macOS permissions may need to be granted again.

## License

MIT
