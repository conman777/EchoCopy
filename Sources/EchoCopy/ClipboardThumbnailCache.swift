import CoreGraphics
import Foundation
import ImageIO

enum ClipboardThumbnailDecoder {
    static func makeThumbnail(
        fromBase64 content: String,
        maximumPixelSize: Int = 560
    ) -> CGImage? {
        guard maximumPixelSize > 0,
              let data = Data(base64Encoded: content),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
    }
}

/// Decodes image previews away from the main thread and retains only a bounded
/// set of reduced-size thumbnails. Full clipboard images remain in history and
/// are decoded only when they are explicitly copied back to the pasteboard.
final class ClipboardThumbnailCache {
    static let shared = ClipboardThumbnailCache()

    private final class ImageBox: NSObject {
        let image: CGImage

        init(_ image: CGImage) {
            self.image = image
        }
    }

    private typealias Completion = (CGImage?) -> Void

    private let cache = NSCache<NSUUID, ImageBox>()
    private let queue = DispatchQueue(
        label: "com.yourcompany.echocopy.thumbnail-decoding",
        qos: .userInitiated
    )

    // Accessed only from `queue`. This prevents multiple visible SwiftUI views
    // from decoding the same history item concurrently.
    private var pendingCompletions: [UUID: [Completion]] = [:]

    private init() {
        cache.countLimit = 60
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    func load(
        itemID: UUID,
        base64Content: String,
        completion: @escaping (CGImage?) -> Void
    ) {
        let cacheKey = itemID as NSUUID
        if let cachedImage = cache.object(forKey: cacheKey)?.image {
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }

        queue.async { [weak self] in
            guard let self else { return }

            if let cachedImage = self.cache.object(forKey: cacheKey)?.image {
                DispatchQueue.main.async {
                    completion(cachedImage)
                }
                return
            }

            if self.pendingCompletions[itemID] != nil {
                self.pendingCompletions[itemID]?.append(completion)
                return
            }

            self.pendingCompletions[itemID] = [completion]
            let image = ClipboardThumbnailDecoder.makeThumbnail(
                fromBase64: base64Content
            )

            if let image {
                let cost = image.bytesPerRow * image.height
                self.cache.setObject(ImageBox(image), forKey: cacheKey, cost: cost)
            }

            let completions = self.pendingCompletions.removeValue(forKey: itemID) ?? []
            DispatchQueue.main.async {
                completions.forEach { $0(image) }
            }
        }
    }
}
