import SwiftUI
import AppKit

/// Popup view shown when Option+V is pressed
struct PopupView: View {
    let history: ClipboardHistory
    let onDismiss: () -> Void
    @State private var hoveredItemId: UUID?
    @State private var searchText = ""

    var body: some View {
        let items = filteredItems

        return VStack(spacing: 12) {
            header

            if items.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            PopupItemRow(
                                item: item,
                                index: index,
                                isHovered: hoveredItemId == item.id,
                                onHover: { hovering in
                                    hoveredItemId = hovering ? item.id : nil
                                },
                                onSelect: {
                                    copyItem(item)
                                    onDismiss()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .background(Color(.windowBackgroundColor))
            }
        }
        .padding(.top, 16)
        .frame(width: Constants.PopupWindow.width, height: Constants.PopupWindow.height)
        .background(
            RoundedRectangle(cornerRadius: Constants.PopupWindow.cornerRadius, style: .continuous)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.PopupWindow.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Constants.PopupWindow.cornerRadius, style: .continuous))
    }

    private var filteredItems: [ClipboardItem] {
        guard !history.items.isEmpty else { return [] }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(history.items.prefix(12))
        }

        let query = trimmed.lowercased()
        let matches = history.items.filter { item in
            if item.content.lowercased().contains(query) {
                return true
            }
            if let filename = item.filename?.lowercased(), filename.contains(query) {
                return true
            }
            return false
        }
        return Array(matches.prefix(12))
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Quick Paste", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Enter to paste • Esc to dismiss")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search recent clips…", text: $searchText)
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.controlBackgroundColor).opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 20))
                .foregroundColor(.secondary)

            Text("No items")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    private func copyItem(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        switch item.contentType {
        case .text, .url:
            NSPasteboard.general.setString(item.content, forType: .string)
            if let rtfBase64 = item.rtfContent, let rtfData = Data(base64Encoded: rtfBase64) {
                NSPasteboard.general.setData(rtfData, forType: .rtf)
            }
        case .image:
            if let data = Data(base64Encoded: item.content),
               let image = NSImage(data: data) {
                NSPasteboard.general.writeObjects([image])
            }
        case .file:
            NSPasteboard.general.setString(item.content, forType: .string)
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12, alignment: .top),
            GridItem(.flexible(), spacing: 12, alignment: .top),
            GridItem(.flexible(), spacing: 12, alignment: .top)
        ]
    }
}
