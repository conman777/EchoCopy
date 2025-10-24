import Foundation
import CoreGraphics

/// Application-wide constants
enum Constants {
    /// Maximum number of clipboard items to keep in history
    static let maxHistoryItems = 500

    /// Interval (in seconds) for polling clipboard changes
    static let clipboardCheckInterval: TimeInterval = 0.5

    /// UserDefaults key for storing clipboard history
    static let clipboardHistoryStorageKey = "clipboardHistory"

    /// Popup window dimensions
    enum PopupWindow {
        static let width: CGFloat = 420
        static let height: CGFloat = 360
        static let cornerRadius: CGFloat = 14
    }

    /// Accessibility
    enum Accessibility {
        static let clipboardManagerDescription = "ClipboardManager"
    }

    /// Screenshot monitoring
    enum ScreenshotMonitor {
        /// Interval (in seconds) for checking for new screenshots
        static let checkInterval: TimeInterval = 2.0

        /// Maximum age (in seconds) for a screenshot to be auto-copied
        /// Prevents copying old screenshots on app launch
        static let maxFileAge: TimeInterval = 10.0

        /// Minimum age (in seconds) before treating a screenshot as ready
        /// Gives macOS time to finish writing the file to disk
        static let minReadyAge: TimeInterval = 0.5
    }
}
