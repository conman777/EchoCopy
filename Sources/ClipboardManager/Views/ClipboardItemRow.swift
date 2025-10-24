import SwiftUI
import AppKit

/// Single-line representation of a clipboard entry with quick actions.
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let history: ClipboardHistory

    @State private var isHovered = false

    private var previewText: String {
        let trimmed = item.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "[Empty]" }
        return trimmed.count > 120 ? "\(trimmed.prefix(120))…" : trimmed
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(previewText)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            actionButton(
                systemName: "doc.on.doc",
                title: "Copy"
            ) {
                copyToClipboard()
            }

            actionButton(
                systemName: item.isPinned ? "pin.fill" : "pin",
                title: item.isPinned ? "Unpin" : "Pin",
                tint: item.isPinned ? .orange : .secondary
            ) {
                history.togglePin(for: item)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.controlBackgroundColor).opacity(isHovered ? 0.85 : 0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isHovered ? 0.15 : 0.05), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func actionButton(systemName: String, title: String, tint: Color = .blue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundColor(tint)
        .help(title)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()

        switch item.contentType {
        case .text, .url, .file:
            NSPasteboard.general.setString(item.content, forType: .string)
            if let rtfBase64 = item.rtfContent, let rtfData = Data(base64Encoded: rtfBase64) {
                NSPasteboard.general.setData(rtfData, forType: .rtf)
            }
        case .image:
            if let data = Data(base64Encoded: item.content),
               let nsImage = NSImage(data: data) {
                NSPasteboard.general.writeObjects([nsImage])
            }
        }
    }
}
