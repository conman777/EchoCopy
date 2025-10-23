import Foundation

/// Enum representing the type of content in a clipboard item
enum ContentType: String, Codable {
    case text
    case image
    case file
    case url
}
