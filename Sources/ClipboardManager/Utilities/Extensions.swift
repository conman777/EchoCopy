import SwiftUI

/// View extension for common utilities
extension View {
    /// Add a border to the top of a view
    func borderTop() -> some View {
        self.overlay(alignment: .top) {
            Divider()
        }
    }
}
