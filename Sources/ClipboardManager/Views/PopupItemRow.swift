import SwiftUI

/// Tile used in the quick-access popup palette
struct PopupItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onSelect: () -> Void

    private var accentColor: Color {
        switch item.contentType {
        case .text: return .blue
        case .image: return .purple
        case .url: return .orange
        case .file: return .green
        }
    }

    private var iconName: String {
        switch item.contentType {
        case .text: return "doc.text"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        }
    }

    private var preview: String {
        let trimmed = item.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "[Empty]" }
        return trimmed.count > 80 ? "\(trimmed.prefix(80))…" : trimmed
    }

    private var keyboardHint: String {
        index < 9 ? "⌥\(index + 1)" : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                    Text(preview)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if !keyboardHint.isEmpty {
                    Text(keyboardHint)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Label(contentLabel, systemImage: "tag")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Label(item.timestamp.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                if item.isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(isHovered ? 0.35 : 0.2), lineWidth: isHovered ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 12 : 8, x: 0, y: 4)
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isHovered)
        .onHover { hovering in
            onHover(hovering)
        }
        .onTapGesture {
            onSelect()
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contentLabel: String {
        switch item.contentType {
        case .text: return "Text"
        case .image: return item.filename ?? "Image"
        case .url: return "Link"
        case .file: return item.filename ?? "File"
        }
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.78))
    }
}
