import SwiftUI
import ImageIO
import UIKit

/// Decoded-image cache + a downsampling loader. `AsyncImage` re-decodes a full-size
/// JPEG every time a cell scrolls back into view and keeps no decoded cache; this
/// downsamples each image to a target pixel size and caches the resulting `UIImage`,
/// so scrolling a large poster grid stays smooth and bounded in memory.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 250
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixel))" as NSString
    }

    /// Synchronous cache peek so a scrolled-back cell shows instantly (no flash).
    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    func load(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        let cacheKey = key(url, maxPixel)
        if let hit = cache.object(forKey: cacheKey) { return hit }
        guard let (data, _) = try? await session.data(from: url),
              let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// A downsampling, decoded-cached replacement for `AsyncImage`. Reloads when `url`
/// changes (correct for recycled cells, no stale-image glitch) and serves cache hits
/// synchronously so scroll-back doesn't flash the placeholder.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    var grayscale: Bool = false
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .grayscale(grayscale ? 1 : 0)
            } else {
                placeholder()
            }
        }
        .task(id: url) { await loadImage() }
    }

    private func loadImage() async {
        guard let url else {
            image = nil
            return
        }
        if let hit = ImageCache.shared.cached(url, maxPixel: maxPixel) {
            image = hit
            return
        }
        image = nil
        let loaded = await ImageCache.shared.load(url, maxPixel: maxPixel)
        if !Task.isCancelled {
            image = loaded
        }
    }
}
