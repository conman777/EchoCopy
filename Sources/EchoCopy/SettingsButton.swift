import AppKit
import SwiftUI

/// Both history surfaces open the same SwiftUI Settings scene.
struct SettingsButton<Label: View>: View {
    private let beforeOpen: () -> Void
    private let label: Label

    init(beforeOpen: @escaping () -> Void = {}, @ViewBuilder label: () -> Label) {
        self.beforeOpen = beforeOpen
        self.label = label()
    }

    var body: some View {
        if #available(macOS 14, *) {
            ModernSettingsButton(beforeOpen: beforeOpen, label: label)
        } else {
            Button {
                beforeOpen()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                label
            }
        }
    }
}

@available(macOS 14, *)
private struct ModernSettingsButton<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    let beforeOpen: () -> Void
    let label: Label

    var body: some View {
        Button {
            beforeOpen()
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            label
        }
    }
}
