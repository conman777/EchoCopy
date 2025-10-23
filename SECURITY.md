# Security Policy

## Overview

ClipboardManager is a privacy-focused clipboard history manager for macOS. This document describes our security practices and policies.

## Security Principles

1. **Transparency** - Code is open and auditable
2. **Minimal permissions** - Only requests necessary OS permissions
3. **Local storage** - Data never leaves your machine
4. **No tracking** - No telemetry, analytics, or phone home
5. **User control** - Users can clear history anytime

## Data Storage

### What We Store
- Clipboard history items (text, images, files, URLs)
- Metadata (timestamps, content type, pin status)
- User preferences (stored in macOS UserDefaults)

### How We Store It
- **Storage location**: `~/Library/Preferences/com.apple.nsuserdefaults.plist`
- **Format**: JSON-encoded, not encrypted
- **Retention**: Until user clears history or uninstalls app
- **Accessibility**: Only accessible to the user's account

### What We Don't Store
- Personal identification
- Location data
- Browsing history (only clipboard content)
- Activity logs
- User analytics

## Permissions

### Required macOS Permissions

**Accessibility Permission** (for global keyboard shortcuts)
- Required for: Option+V popup, Cmd+Alt+1-9 quick paste
- Purpose: Capture global keyboard events
- Can be revoked in: System Preferences → Security & Privacy → Accessibility

### Optional Permissions
- None - app runs with minimum required permissions

## Clipboard Content Security

### Text Content
- Stored as plain text
- No encryption applied
- Accessible via standard clipboard APIs
- Can be cleared with Cmd+Shift+K

### Image Content
- Stored as base64-encoded binary data
- No compression or format conversion
- Size limited by available storage
- Can be cleared individually or with history clear

### Sensitive Data Warning
**We recommend:**
- Don't copy passwords/tokens to clipboard
- Don't enable clipboard history for highly sensitive work
- Clear history before sharing your computer (Cmd+Shift+K)
- Use macOS Keychain for password storage instead

## Privacy Considerations

### What ClipboardManager Can See
- All clipboard content while app is running
- Metadata about what you copy (type, time)
- Which apps you're copying from

### What ClipboardManager Cannot See
- Your keystrokes or typing (only clipboard content)
- Your browsing activity outside of copying URLs
- Your file system (only clipboard paths, not actual files)
- System passwords or keychain data

### Data Transmission
**Zero network connectivity**
- No cloud sync
- No remote backups
- No analytics reporting
- No error reporting (handled locally)

## Code Security

### Input Validation
- All clipboard content is validated before storage
- Empty items are rejected
- Duplicate consecutive items are rejected
- String validation prevents injection attacks

### Memory Management
- Swift automatic memory management (ARC)
- No manual memory manipulation
- No buffer overflows possible
- Closures properly capture weak self references

### Denial of Service Protection
- Maximum 500 items in history (prevents memory exhaustion)
- Clipboard monitoring runs at 500ms intervals (prevents CPU thrashing)
- Search filtering is O(n) with no denial of service vectors

## Accessibility Permission

### Why It's Needed
Global keyboard shortcuts (Option+V, Cmd+Alt+1-9) require accessibility permission to detect key events outside the app window.

### What It Allows
- Detecting global keyboard events
- Showing popup window on Option+V
- Quick-pasting items with Cmd+Alt+1-9

### What It Doesn't Allow
- Capturing user keystrokes
- Monitoring other apps
- Accessing system passwords
- Screen recording

### How to Verify
1. System Preferences → Security & Privacy → Accessibility
2. Check "ClipboardManager" is enabled
3. You can revoke this anytime to disable global shortcuts

## macOS Sandboxing

### Current Status
- **Not sandboxed** - Runs with full user permissions
- **Why not**: Clipboard access requires unsandboxed entitlements

### Future Considerations
If distribution via Mac App Store becomes desired, we would implement sandboxing with appropriate entitlements.

## Code Review

All code changes undergo review for:
- Input validation
- Memory safety
- Weak reference correctness
- Error handling
- Resource cleanup

## Vulnerability Reporting

To report a security vulnerability:

1. **Do not** open a public GitHub issue
2. **Do** email security details to: [maintainer email]
3. Include:
   - Vulnerability description
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will:
- Confirm receipt within 24 hours
- Investigate thoroughly
- Work on a fix
- Provide a timeline for patch release
- Credit the researcher (unless requested otherwise)

## Changelog

See `CHANGELOG.md` for security-related updates to the application.

## Dependencies

### Framework Dependencies
- **AppKit** - macOS system framework (Apple security oversight)
- **SwiftUI** - macOS UI framework (Apple security oversight)
- **Foundation** - macOS standard library (Apple security oversight)
- **Combine** - Reactive framework (Apple)
- **ApplicationServices** - System services framework (Apple)

### Build Tools
- **Swift Compiler** - Apple compiler (open source, auditable)
- **SwiftFormat** - Code formatter (open source)
- **SwiftLint** - Code quality (open source)

**No third-party runtime dependencies** - Reduces attack surface significantly.

## Security Best Practices for Users

1. **Clear history regularly** - Cmd+Shift+K
2. **Verify accessibility permissions** - Check System Preferences monthly
3. **Keep macOS updated** - Security updates are crucial
4. **Don't copy sensitive data** - Use Keychain for passwords
5. **Disable global shortcuts if not needed** - Reduces permission scope

## Compliance

- **GDPR**: No personal data collected or transmitted
- **CCPA**: No data sales, all data local
- **HIPAA**: Not suitable for healthcare data (clipboard is unencrypted)
- **PCI-DSS**: Not suitable for payment card data storage

## Future Security Improvements

Potential enhancements under consideration:
- Optional encryption for clipboard history
- Password-protection for accessing history
- Scheduled automatic history clearing
- Per-app clipboard restrictions
- Export history with encryption

## Questions?

For security questions or concerns, please contact the maintainer or open a discussion on GitHub.

---

Last updated: October 2024
Version: 1.0.0
