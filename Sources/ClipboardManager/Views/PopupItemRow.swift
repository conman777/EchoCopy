import SwiftUI

/// Single item row in the popup window
struct PopupItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onSelect: () -> Void

    var contentIcon: String {
        switch item.contentType {
        case .text: return "doc.text.fill"
        case .image: return "photo.fill"
        case .url: return "link"
        case .file: return "doc.fill"
        }
    }

    var iconColor: Color {
        switch item.contentType {
        case .text: return .blue
        case .image: return .purple
        case .url: return .orange
        case .file: return .green
        }
    }

    var contentPreview: String {
        switch item.contentType {
        case .text:
            let lines = item.content.components(separatedBy: .newlines)
            let firstLine = lines.first ?? ""
            return firstLine.count > 60 ? String(firstLine.prefix(60)) + "..." : firstLine
        case .image: return item.filename ?? "Image"
        case .url: return item.content
        case .file: return item.filename ?? "File"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            // Small icon
            Circle()
                .fill(iconColor.opacity(isHovered ? 0.2 : 0.15))
                .frame(width: 6, height: 6)

            // Content - just the text preview
            Text(contentPreview)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            // Copy indicator
            if isHovered {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(iconColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHovered ? Color(.controlBackgroundColor).opacity(0.7) : Color(.controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    isHovered ? iconColor.opacity(0.4) : Color.clear,
                    lineWidth: isHovered ? 1 : 0
                )
        )
        .animation(.spring(response: 0.15, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            onHover(hovering)
        }
        .onTapGesture {
            onSelect()
        }
        .contentShape(Rectangle())
    }
}
