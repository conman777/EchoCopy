import SwiftUI
import AppKit

/// Popup view shown when Option+V is pressed
struct PopupView: View {
    let history: ClipboardHistory
    let onDismiss: () -> Void
    @State private var hoveredItemId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if history.items.isEmpty {
                emptyStateView
            } else {
                listView
            }
        }
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

    private var listView: some View {
        ScrollView(showsIndicators: true) {
            VStack(spacing: 1.5) {
                ForEach(Array(history.items.enumerated()), id: \.element.id) { index, item in
                    PopupItemRow(
                        item: item,
                        index: index,
                        isHovered: hoveredItemId == item.id,
                        onHover: { hovered in
                            hoveredItemId = hovered ? item.id : nil
                        },
                        onSelect: {
                            copyItem(item)
                            onDismiss()
                        }
                    )
                }
            }
            .padding(4)
        }
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
}
