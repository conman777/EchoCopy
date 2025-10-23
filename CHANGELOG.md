# Changelog

All notable changes to ClipboardManager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Comprehensive documentation structure
- SwiftFormat and SwiftLint configuration
- Git hooks for code quality gates
- CI/CD pipeline with GitHub Actions
- Modular codebase with separate concerns

### Changed
- Refactored monolithic App.swift into separate modules
- Improved error handling in persistence layer
- Added input validation for clipboard content
- Enhanced code organization following CLAUDE.md guidelines

### Fixed
- **Critical**: togglePin() bug that lost content metadata
- Silent failures in clipboard history save/load

## [1.0.0] - 2024-10-20

### Added
- Initial ClipboardManager release
- Clipboard history tracking (up to 500 items)
- Search functionality for clipboard items
- Pin/unpin frequently used items
- Keyboard shortcuts:
  - Option+V: Show clipboard popup
  - Cmd+Alt+1-9: Quick paste recent items
  - Cmd+Shift+K: Clear all history
- Menu bar integration with top 10 quick access
- RTF formatting preservation for rich text
- Support for multiple content types: text, images, URLs, files
- Persistent storage via UserDefaults
- Privacy-focused: No network access, local storage only

### Technical
- Built with SwiftUI and AppKit
- Swift Package Manager project structure
- macOS 13.0+ support
- Universal binary (Apple Silicon + Intel)
- Zero external dependencies

---

## Release Notes Format

When creating a new release, follow this format:

```markdown
## [Version] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security-related fixes
```

## Versioning

- **MAJOR**: Breaking changes, UI redesigns
- **MINOR**: New features, non-breaking changes
- **PATCH**: Bug fixes, hotfixes

Example:
- 1.0.0 - Initial release
- 1.1.0 - Added image support
- 1.1.1 - Fixed menu bar icon bug
- 2.0.0 - Major UI redesign

## Release Process

1. Update CHANGELOG.md with new version
2. Commit with message: `release: bump version to X.Y.Z`
3. Create Git tag: `git tag vX.Y.Z`
4. Push: `git push && git push --tags`
5. GitHub Actions builds and creates release automatically
6. Announce release on relevant platforms

See `docs/workflows/RELEASE_PROCESS.md` for detailed instructions.
