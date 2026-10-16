import CoreGraphics
import Foundation
import ImageIO

enum ClipboardThumbnailDecoder {
    static func makeThumbnail(
        fromBase64 content: String,
        maximumPixelSize: Int = 320
    ) -> CGImage? {
        guard let data = Data(base64Encoded: content) else { return nil }
        return makeThumbnail(from: data, maximumPixelSize: maximumPixelSize)
    }

    static func makeThumbnail(
        from data: Data,
        maximumPixelSize: Int = 320
    ) -> CGImage? {
        guard maximumPixelSize > 0,
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
/// set of reduced-size thumbnails. Full clipboard images stay in their encrypted
/// payload files and are read only to build a thumbnail or to paste.
final class ClipboardThumbnailCache {
    static let shared = ClipboardThumbnailCache()

    private final class ImageBox: NSObject {
        let image: CGImage

        init(_ image: CGImage) {
            self.image = image
        }
    }

    private let cache = NSCache<NSUUID, ImageBox>()
    private let queue = DispatchQueue(
        label: "com.yourcompany.echocopy.thumbnail-decoding",
        qos: .userInitiated
    )

    private init() {
        cache.countLimit = 32
        cache.totalCostLimit = 16 * 1_024 * 1_024
    }

    func load(
        itemID: UUID,
        imageData: @escaping () -> Data?,
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

            let image = imageData().flatMap {
                ClipboardThumbnailDecoder.makeThumbnail(from: $0)
            }

            if let image {
                let cost = image.bytesPerRow * image.height
                self.cache.setObject(ImageBox(image), forKey: cacheKey, cost: cost)
            }

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
