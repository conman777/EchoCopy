# Swift Code Conventions

This document specifies the coding standards and conventions used in ClipboardManager.

## Naming Conventions

### Files and Types
- **Classes**: PascalCase (e.g., `MenuBarManager`, `AppDelegate`)
- **Structs**: PascalCase (e.g., `ContentView`, `ClipboardItem`)
- **Enums**: PascalCase (e.g., `ContentType`)
- **Protocols**: PascalCase (e.g., `NSApplicationDelegate`)
- **Files**: Match the primary type name (e.g., `MenuBarManager.swift`)

### Variables and Functions
- **Constants**: camelCase (e.g., `maxItems`, `checkInterval`)
- **Variables**: camelCase (e.g., `currentItem`, `isHovered`)
- **Functions**: camelCase with imperative verbs (e.g., `addItem()`, `saveHistory()`)
- **Private members**: Prefix with `_` if implementation detail (e.g., `_WindowDetectorView`)

### Abbreviations
- Avoid abbreviations (e.g., use `ContentType` not `CT`)
- Exception: Standard short names (`id`, `x`, `y`, `ws` for WebSocket)

## Code Organization

### File Structure
Every Swift file follows this structure:

```swift
import Foundation
import SwiftUI

// MARK: - Type Definition

class/struct/enum MyType {
    // MARK: - Properties

    @Published var item: String?
    private var timer: Timer?

    // MARK: - Lifecycle

    init() { }

    // MARK: - Public Methods

    func publicMethod() { }

    // MARK: - Private Methods

    private func privateMethod() { }

    // MARK: - Cleanup

    deinit { }
}
```

### MARK Comments
Use `// MARK: - SectionName` to organize code sections:
- Properties
- Lifecycle (init, deinit)
- Public Methods
- Private Methods
- Cleanup (deinit)
- Setup / Configuration

## Type and Style Rules

### Unwrapping Optionals
```swift
// Good: Guard early for defensive programming
func process(_ value: String?) {
    guard let value = value else { return }
    // Use value safely
}

// Avoid: Multiple nested unwraps
if let a = a {
    if let b = b {
        // hard to read
    }
}
```

### Error Handling
```swift
// Good: Explicit error handling
do {
    let data = try JSONEncoder().encode(items)
    UserDefaults.standard.set(data, key: "key")
} catch {
    print("❌ Error saving: \(error.localizedDescription)")
}

// Avoid: Silent failures
try? JSONEncoder().encode(items)
```

### Closures
```swift
// Good: Clear closure syntax
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
    self?.handleEvent(event)
}

// Avoid: Unclear trailing closures without capture list
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    // might cause retain cycles
}
```

### Weak References
Always use `[weak self]` in closures to prevent retain cycles:
```swift
// Good
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
    self?.handleEvent(event)
}

// Bad: Creates retain cycle
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    self.handleEvent(event)
}
```

## Comments and Documentation

### When to Comment
Only comment **critical caveats** or **non-obvious intent**:

```swift
// Good: Explains WHY not WHAT
// BUG FIX: Use updating() method to preserve all fields
// The original code lost contentType, filename, rtfContent
let toggled = items[index].updating(isPinned: !items[index].isPinned)

// Bad: Explains WHAT (code is self-explanatory)
// Increase the index by 1
index += 1
```

### Documentation Comments
Use `///` for public APIs:

```swift
/// Add a new item to the history (or ignore if invalid/duplicate)
/// - Parameters:
///   - content: The clipboard content (must not be empty after trimming)
///   - contentType: Type of content (default: .text)
/// - Returns: Nothing (updates internal state)
func addItem(_ content: String, contentType: ContentType = .text) { }
```

## SwiftUI Conventions

### View Structure
```swift
struct MyView: View {
    @State private var value = ""
    @EnvironmentObject var model: Model

    var body: some View {
        VStack {
            Text("Content")
        }
    }

    private var someHelper: some View {
        Text("Helper")
    }
}
```

### State Management
- `@State` for simple local state
- `@EnvironmentObject` for app-wide data
- `@Published` in observable objects
- Never use `@StateObject` in view struct (`@StateObject` goes in parent that owns lifecycle)

### Modifiers Order
Order SwiftUI modifiers logically:
```swift
Text("Label")
    .font(.system(size: 12))           // Style
    .foregroundColor(.secondary)       // Appearance
    .lineLimit(1)                      // Layout
    .truncationMode(.tail)             // Truncation
    .padding(8)                        // Spacing
    .background(Color.gray)            // Background
    .clipShape(RoundedRectangle(...)) // Clipping
    .onTapGesture { action() }        // Gestures
```

## Access Control

Use explicit access levels:

```swift
// Public (if needed)
public func publicAPI() { }

// Internal (default, don't need to write)
internal func internalFunction() { }

// Private to class/struct
private func privateMethod() { }

// Private to file
fileprivate func filePrivate() { }
```

## Constants

Define all magic numbers in `Constants.swift`:

```swift
// Good: In Constants.swift
enum Constants {
    static let maxItems = 500
    static let checkInterval: TimeInterval = 0.5
}

// Usage
let history = ClipboardHistory()
history.maxItems // Error: access Constants.maxHistoryItems

// Bad: Magic numbers in code
if items.count > 500 { // What is 500?
    items = Array(items.prefix(500))
}
```

## Formatting Rules

### Line Length
- Warning at 120 characters
- Error at 150 characters
- Use SwiftFormat to enforce

### Indentation
- 4 spaces (not tabs)
- Consistent across all files

### Blank Lines
- Two blank lines between types
- One blank line between methods
- Zero blank lines between MARK comments and first item

## Code Smells to Avoid

| Smell | Problem | Solution |
|-------|---------|----------|
| Long functions (>50 lines) | Hard to test | Extract smaller functions |
| Deep nesting (>3 levels) | Hard to read | Extract helper methods |
| Boolean parameters | Unclear intent | Use enum instead |
| Silently failing code | Hidden bugs | Always throw or log errors |
| Magic numbers | Unclear intent | Move to Constants |
| Force unwrapping `!` | Crashes | Use guard/if let |

## Imports

Keep imports organized:

```swift
// System frameworks first (alphabetical)
import AppKit
import Combine
import Foundation
import SwiftUI

// Custom imports
import ArchitectureModule
```

## Testing Conventions

See `docs/development/TESTING_GUIDE.md` for detailed testing guidelines.

Key points:
- Test file next to source file with `.swift` → `.swift` naming
- Test class names: `XYZTests` (e.g., `ClipboardHistoryTests`)
- Test method names: `test[Feature][Condition][Expected]` (e.g., `testAddItemWithValidContent`)
- Use Arrange-Act-Assert pattern

## Swift Package Manager (SPM)

When adding dependencies:
```swift
// Good: Specific version ranges
.package(url: "...", from: "1.0.0")

// Avoid: Unspecified ranges
.package(url: "...", branch: "main")
```

We prefer no external dependencies when possible to keep the codebase simple and audit-able.

---

See related docs:
- `SYSTEM_ARCHITECTURE.md` - How these conventions fit into the architecture
- `SETUP.md` - How to run formatters that enforce these rules
