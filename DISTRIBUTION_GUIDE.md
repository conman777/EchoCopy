# Clipboard Manager - Distribution Guide

## ⚠️ Important: Choose Your Distribution Method

Your app uses **Accessibility Permissions** for global keyboard shortcuts (Option+V). This makes it **unsuitable for Mac App Store distribution** because:
- App Store apps must be sandboxed
- Sandboxed apps cannot request accessibility permissions
- Apple typically rejects clipboard managers

**Recommended:** **Direct Distribution with Notarization**

---

## Direct Distribution (Recommended)

### Prerequisites

1. **Apple Developer Program** ($99/year)
   - Sign up at https://developer.apple.com/programs/
   - Wait for approval (1-2 days)

2. **Install Xcode** (for codesign and notary tools)
   - Download from Mac App Store
   - Open once to accept license

### Step 1: Get Your Developer ID

1. Open **Xcode** → **Settings** → **Accounts**
2. Click **+** and sign in with your Apple ID
3. Select your team → **Manage Certificates**
4. Click **+** → **Developer ID Application**
5. Note your **Team ID** (shown under your name)

### Step 2: Create App-Specific Password

1. Go to https://appleid.apple.com/account/manage
2. Sign in with your Apple ID
3. Under **Security** → **App-Specific Passwords**
4. Click **Generate Password**
5. Name it "Notarization"
6. **Save this password securely!**

### Step 3: Configure Build Script

Edit `build-and-notarize.sh`:

```bash
# Update these lines with your actual values:
DEVELOPER_ID="Developer ID Application: Your Name (YOUR_TEAM_ID)"
BUNDLE_ID="com.yourcompany.clipboardmanager"  # Must be unique
```

To find your Developer ID certificate name:
```bash
security find-identity -v -p codesigning
```

### Step 4: Build and Sign

```bash
cd "/Users/conordart/Documents/coding projects/apple notes app/copynoteapple"
./build-and-notarize.sh
```

This will:
- ✅ Build a universal binary (Intel + Apple Silicon)
- ✅ Create an app bundle
- ✅ Code sign with hardened runtime
- ✅ Create a DMG for distribution
- ✅ Sign the DMG

### Step 5: Notarize with Apple

After the build completes, run:

```bash
# Replace with your actual values
xcrun notarytool submit ClipboardManager-1.0.0.dmg \
  --apple-id your.email@example.com \
  --team-id YOUR_TEAM_ID \
  --password xxxx-xxxx-xxxx-xxxx \
  --wait
```

This usually takes 5-15 minutes. You'll see:
```
Processing complete
  id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  status: Accepted
```

### Step 6: Staple the Notarization

```bash
xcrun stapler staple ClipboardManager-1.0.0.dmg
```

### Step 7: Verify

```bash
spctl -a -vv -t install ClipboardManager-1.0.0.dmg
```

You should see:
```
ClipboardManager-1.0.0.dmg: accepted
source=Notarized Developer ID
```

### Step 8: Distribute!

Your `ClipboardManager-1.0.0.dmg` is now ready to distribute:
- Upload to your website
- Share on GitHub Releases
- Distribute directly to users

Users can install by:
1. Double-clicking the DMG
2. Dragging the app to Applications
3. Opening it (macOS will verify the notarization automatically)

---

## Troubleshooting

### "Unable to find utility 'notarytool'"

Install Xcode Command Line Tools:
```bash
xcode-select --install
```

### "codesign: Developer ID Application not found"

1. Open Xcode → Settings → Accounts
2. Select your team → Manage Certificates
3. Create "Developer ID Application" certificate
4. Run `security find-identity -v -p codesigning` to verify

### "Invalid Code Signature"

Make sure your `ClipboardManager.entitlements` file exists and is valid:
```bash
cat ClipboardManager.entitlements
```

### Notarization Failed

Check the detailed log:
```bash
xcrun notarytool log SUBMISSION_ID --apple-id YOUR_EMAIL --team-id TEAM_ID --password APP_PASSWORD
```

Common issues:
- Missing hardened runtime
- Invalid entitlements
- Unsigned embedded frameworks

---

## Updating Your App

1. Update version in `build-and-notarize.sh`:
   ```bash
   VERSION="1.1.0"
   ```

2. Update `CFBundleShortVersionString` in `Info.plist`

3. Rebuild, notarize, and distribute the new DMG

---

## Alternative: Sparkle Framework (Auto-Updates)

For automatic updates, integrate Sparkle:
1. Add Sparkle framework: https://sparkle-project.org/
2. Create an appcast XML file
3. Host updates on your server
4. Users get automatic update notifications

---

## Resources

- [Apple Notarization Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Sparkle Framework](https://sparkle-project.org/)
- [Gatekeeper](https://support.apple.com/en-us/HT202491)

---

## Need Help?

- Check Apple Developer Forums: https://developer.apple.com/forums/
- File an issue on GitHub
- Contact Apple Developer Support (included with your $99/year membership)
