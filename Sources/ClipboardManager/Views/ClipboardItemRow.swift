import SwiftUI
import AppKit

/// Row view for a single clipboard item in the main history list
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let history: ClipboardHistory
    @State private var isHovered = false

    var contentIcon: String {
        switch item.contentType {
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .url:
            return "link"
        case .file:
            return "doc"
        }
    }

    var iconColor: Color {
        switch item.contentType {
        case .text:
            return .blue
        case .image:
            return .purple
        case .url:
            return .orange
        case .file:
            return .green
        }
    }

    var contentPreview: String {
        switch item.contentType {
        case .text:
            return item.content.count > 100 ? String(item.content.prefix(100)) + "..." : item.content
        case .image:
            return "[Image]"
        case .url:
            return item.content
        case .file:
            return item.filename ?? "[File]"
        }
    }

    var contentTypeLabel: String {
        switch item.contentType {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .url:
            return "Link"
        case .file:
            return "File"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                    Image(systemName: contentIcon)
                        .foregroundColor(iconColor)
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(width: 36, height: 36)

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(contentPreview)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    HStack(spacing: 8) {
                        Text(contentTypeLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(4)

                        Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: {
                        pasteItem()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Paste to clipboard")
                    .symbolRenderingMode(.monochrome)
                    .opacity(isHovered ? 1 : 0.85)

                    Button(action: {
                        history.togglePin(for: item)
                    }) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(item.isPinned ? .orange : .secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "Unpin" : "Pin")
                    .symbolRenderingMode(.monochrome)
                    .opacity(isHovered ? 1 : 0.85)
                }
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.controlBackgroundColor).opacity(isHovered ? 0.95 : 0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isHovered ? 0.18 : 0.08), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
    }

    private func pasteItem() {
        NSPasteboard.general.clearContents()

        switch item.contentType {
        case .text, .url:
            NSPasteboard.general.setString(item.content, forType: .string)

            // Restore RTF formatting if available
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
