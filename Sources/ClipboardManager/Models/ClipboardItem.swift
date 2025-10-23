import Foundation

/// Represents a single clipboard history entry
struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    let content: String  // Plain text or base64 for images
    let contentType: ContentType
    let timestamp: Date
    let isPinned: Bool
    let filename: String?  // For file/image references
    let rtfContent: String?  // Rich Text Format (base64 encoded)

    init(
        content: String,
        contentType: ContentType = .text,
        isPinned: Bool = false,
        filename: String? = nil,
        rtfContent: String? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.contentType = contentType
        self.timestamp = Date()
        self.isPinned = isPinned
        self.filename = filename
        self.rtfContent = rtfContent
    }

    /// Create a new item preserving all fields but with updated values
    /// - Parameters:
    ///   - id: UUID to preserve (defaults to self.id)
    ///   - content: Clipboard content (defaults to self.content)
    ///   - contentType: Type of content (defaults to self.contentType)
    ///   - timestamp: When item was added (defaults to self.timestamp)
    ///   - isPinned: Whether item is pinned (defaults to self.isPinned)
    ///   - filename: Optional filename (defaults to self.filename)
    ///   - rtfContent: Optional RTF data (defaults to self.rtfContent)
    /// - Returns: New ClipboardItem with preserved fields
    func updating(
        id: UUID? = nil,
        content: String? = nil,
        contentType: ContentType? = nil,
        timestamp: Date? = nil,
        isPinned: Bool? = nil,
        filename: String? = nil,
        rtfContent: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id ?? self.id,
            content: content ?? self.content,
            contentType: contentType ?? self.contentType,
            timestamp: timestamp ?? self.timestamp,
            isPinned: isPinned ?? self.isPinned,
            filename: filename ?? self.filename,
            rtfContent: rtfContent ?? self.rtfContent
        )
    }

    /// Initialize with custom values - used by `updating()` method
    private init(
        id: UUID,
        content: String,
        contentType: ContentType,
        timestamp: Date,
        isPinned: Bool,
        filename: String?,
        rtfContent: String?
    ) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.filename = filename
        self.rtfContent = rtfContent
    }
}
