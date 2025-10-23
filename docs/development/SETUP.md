# Local Development Setup

## Prerequisites

### System Requirements
- macOS 13.0 or later
- Xcode 15.0+ (for SwiftUI features)
- Git for version control

### Install Xcode
```bash
# Via Mac App Store
open "macappstore://apps.apple.com/app/xcode/id497799835"

# Or via command line
xcode-select --install
```

## Development Tools Setup

### 1. SwiftFormat (Code Formatter)

Install SwiftFormat:
```bash
brew install swiftformat
```

Verify installation:
```bash
swiftformat --version
```

Format the project:
```bash
swiftformat Sources/
```

Check formatting without modifying files:
```bash
swiftformat --lint Sources/
```

### 2. SwiftLint (Code Quality)

Install SwiftLint:
```bash
brew install swiftlint
```

Verify installation:
```bash
swiftlint version
```

Run linter:
```bash
swiftlint lint
```

See warnings without failing:
```bash
swiftlint
```

### 3. Git Hooks (Automation)

Initialize git hooks:
```bash
./.githooks/setup.sh
```

This prevents committing code that fails formatting or linting.

## Project Structure

```
copynoteapple/
├── .github/                     # GitHub Actions (CI/CD)
├── .githooks/                   # Git hooks for pre-commit checks
├── .swiftformat                 # SwiftFormat configuration
├── .swiftlint.yml              # SwiftLint configuration
├── Package.swift               # Swift Package manifest
├── Sources/
│   └── ClipboardManager/
│       ├── App.swift           # Main entry point
│       ├── Models/
│       │   ├── ContentType.swift
│       │   ├── ClipboardItem.swift
│       │   └── ClipboardHistory.swift
│       ├── Services/
│       │   └── ClipboardMonitor.swift
│       ├── Views/
│       │   ├── ContentView.swift
│       │   ├── ClipboardItemRow.swift
│       │   ├── PopupView.swift
│       │   └── PopupItemRow.swift
│       ├── AppKit/
│       │   ├── AppDelegate.swift
│       │   ├── MenuBarManager.swift
│       │   ├── GlobalShortcutHandler.swift
│       │   ├── PopupWindowManager.swift
│       │   ├── MenuBarWindow.swift
│       │   └── MenuBarWindowDelegate.swift
│       └── Utilities/
│           ├── Constants.swift
│           ├── Extensions.swift
│           └── WindowAccessor.swift
├── docs/                       # Documentation
├── README.md
└── CHANGELOG.md
```

## Building the Project

### Using Swift Package Manager

Build for development (debug):
```bash
swift build
```

Build for release (optimized):
```bash
swift build -c release
```

Run the app directly:
```bash
swift run ClipboardManager
```

### Using Xcode

Open the project:
```bash
open .
# Or if using Xcode:
open ClipboardManager.xcodeproj  # (if available)
```

Build: `Cmd+B`
Run: `Cmd+R`

## Code Quality Workflow

### Before Committing

1. **Format code**:
   ```bash
   swiftformat Sources/
   ```

2. **Run linter**:
   ```bash
   swiftlint lint
   ```

   Fix any warnings before committing.

3. **Build the project**:
   ```bash
   swift build
   ```

4. **Verify app runs**:
   ```bash
   swift run ClipboardManager
   ```

5. **Commit changes**:
   ```bash
   git add .
   git commit -m "feat: describe your change"
   ```

### Git Hooks (Automatic)

If you've set up `.githooks/pre-commit`, these checks run automatically before each commit.

## Debugging

### Enable Debug Output

The app uses `print()` statements for logging. Common log patterns:

- `❌ Error...` - Errors that impact functionality
- `⚠️ Warning...` - Issues that don't prevent functionality
- `✅ Success...` - Important completions

View logs in the console while running:
```bash
swift run ClipboardManager 2>&1 | tee debug.log
```

### Common Issues

See `docs/troubleshooting/BUILD_ERRORS.md` for build issues.
See `docs/troubleshooting/COMMON_ISSUES.md` for runtime issues.

## Swift Conventions

This project follows specific Swift naming and style conventions.
See `docs/development/SWIFT_CONVENTIONS.md` for details.

## Next Steps

1. Read `SYSTEM_ARCHITECTURE.md` to understand the codebase structure
2. Review `SWIFT_CONVENTIONS.md` for code style requirements
3. Explore individual components in the appropriate docs
4. Make your changes following the guidelines
5. Verify with format/lint/build before committing
