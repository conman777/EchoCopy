import SwiftUI

/// Main clipboard history screen with a simple single-line list layout.
struct ContentView: View {
    @EnvironmentObject var history: ClipboardHistory
    @State private var searchText = ""
    @State private var showPinnedOnly = false

    private var filteredItems: [ClipboardItem] {
        let baseItems = showPinnedOnly ? history.items.filter { $0.isPinned } : history.items
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return baseItems
        }

        let lowercasedQuery = trimmedQuery.lowercased()

        return baseItems.filter { item in
            if item.content.lowercased().contains(lowercasedQuery) {
                return true
            }

            if let filename = item.filename?.lowercased(), filename.contains(lowercasedQuery) {
                return true
            }

            return false
        }
    }

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor)
                .ignoresSafeArea()
                .background(WindowAccessor { window in
                    if let app = NSApp.delegate as? AppDelegate {
                        app.applyWindowBehavior(to: window)
                    }
                })

            VStack(spacing: 0) {
                headerView

                Divider()

                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    listView
                }

                footerView
            }
        }
        .frame(minWidth: 340, minHeight: 320)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clipboard History")
                .font(.system(size: 20, weight: .semibold))

            HStack(spacing: 12) {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)

                Toggle(isOn: $showPinnedOnly) {
                    Label("Pinned only", systemImage: "pin")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.controlBackgroundColor).opacity(0.92))
    }

    private var listView: some View {
        List {
            ForEach(filteredItems) { item in
                ClipboardItemRow(item: item, history: history)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color(.windowBackgroundColor))
            }
        }
        .listStyle(.plain)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("Nothing copied yet")
                .font(.system(size: 15, weight: .semibold))

            Text("Copy some text or files and they will show up here automatically.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerView: some View {
        HStack {
            Label("\(history.items.count) items stored", systemImage: "tray.full")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Button(role: .destructive) {
                history.clearHistory()
            } label: {
                Label("Clear All", systemImage: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(history.items.isEmpty)
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.controlBackgroundColor).opacity(0.9))
        .borderTop()
    }
}
