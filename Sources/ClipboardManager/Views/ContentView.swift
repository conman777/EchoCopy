import SwiftUI

/// Main content view for the clipboard history manager
struct ContentView: View {
    @EnvironmentObject var history: ClipboardHistory
    @State private var searchText = ""

    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return history.items
        }
        return history.items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor).ignoresSafeArea()
                .background(WindowAccessor { window in
                    // Ensure our AppKit configuration is applied to the exact SwiftUI window
                    if let app = NSApp.delegate as? AppDelegate {
                        app.applyWindowBehavior(to: window)
                    }
                })

            VStack(spacing: 0) {
                // Header with title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clipboard History")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)

                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.controlBackgroundColor).opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .padding(12)

                // Content
                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(filteredItems) { item in
                                ClipboardItemRow(item: item, history: history)
                            }
                        }
                        .padding(8)
                    }
                }

                // Footer
                footerView
            }
        }
        .frame(minWidth: 320, minHeight: 240)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundColor(.secondary)

            Text("No items yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Text("Copy something to get started")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Text("Use Command+Shift+K to clear history quickly.")
                .font(.system(size: 12))
                .foregroundColor(Color.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerView: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                history.clearHistory()
            } label: {
                Label("Clear All", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(history.items.count) items")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Text("Command+Shift+K clears history")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .borderTop()
    }
}
