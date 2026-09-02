# EchoCopy - Distribution Guide

## ⚠️ Important: Choose Your Distribution Method

EchoCopy uses **Accessibility Permissions** for one-click paste and optional screenshot capture. This makes it **unsuitable for Mac App Store distribution** because:
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

Provide the release configuration through the environment when invoking `build-and-notarize.sh`:

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (YOUR_TEAM_ID)"
export BUNDLE_ID="com.yourcompany.echocopy"
export VERSION="1.0.7"
export BUILD_NUMBER="7"
export RELEASE_TAG="v1.0.7"
./build-and-notarize.sh
```

The distribution build refuses to continue unless `VERSION`, `BUILD_NUMBER`,
`RELEASE_TAG`, and `Sources/EchoCopy/Info.plist` agree. This prevents a GitHub
release from advertising a version different from the app inside it.

Keep `com.yourcompany.echocopy` for upgrades of the existing app. Changing the
bundle identifier creates a new macOS Accessibility permission and preferences
identity, so existing users would need an explicit migration and permission
grant before such a change ships.

To find your Developer ID certificate name:
```bash
security find-identity -v -p codesigning
```

### Step 4: Build and Sign

```bash
cd "/Users/yourname/path/to/EchoCopy"
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
xcrun notarytool submit EchoCopy-1.0.7.dmg \
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
xcrun stapler staple EchoCopy-1.0.7.dmg
```

### Step 7: Verify

```bash
spctl -a -vv -t install EchoCopy-1.0.7.dmg
```

You should see:
```
EchoCopy-1.0.7.dmg: accepted
source=Notarized Developer ID
```

### Step 8: Distribute!

Your `EchoCopy-1.0.7.dmg` is now ready to distribute:
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

Make sure your `EchoCopy.entitlements` file exists and is valid:
```bash
cat EchoCopy.entitlements
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

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Sources/EchoCopy/Info.plist`.

2. Set matching release values:
   ```bash
   export VERSION="1.1.0"
   export BUILD_NUMBER="8"
   export RELEASE_TAG="v1.1.0"
   ```

3. Rebuild, notarize, and publish the DMG under exactly that release tag. The
   build stops with an error if any version value disagrees.

---

## Future automatic updates

If automatic updates are added later, integrate a signed updater such as Sparkle:
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
