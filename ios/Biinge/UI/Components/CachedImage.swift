import SwiftUI
import ImageIO
import UIKit

/// Downsampling decoded-image cache so poster grids scroll smoothly within bounded memory
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    /// Coalesces concurrent loads of the same image into one download + decode
    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        // bounded by decoded-bitmap bytes; a count limit alone could balloon to hundreds of MB
        cache.totalCostLimit = 128 * 1024 * 1024
        cache.countLimit = 500
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixel))" as NSString
    }

    /// Synchronous cache peek so a scrolled-back cell shows instantly (no flash)
    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    func load(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        let cacheKey = key(url, maxPixel)
        if let hit = cache.object(forKey: cacheKey) { return hit }

        let (task, isCreator) = inFlightTask(for: cacheKey) {
            Task { [session] () -> UIImage? in
                guard let (data, _) = try? await session.data(from: url) else { return nil }
                return Self.downsample(data, maxPixel: maxPixel)
            }
        }

        let image = await task.value
        // only the creator caches and unregisters, cache-before-clear so no request misses both
        if isCreator {
            if let image {
                // Cost = decoded bitmap footprint, so totalCostLimit bounds real memory
                let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                cache.setObject(image, forKey: cacheKey, cost: cost)
            }
            clearInFlight(cacheKey)
        }
        return image
    }

    /// Returns or registers the in-flight task for `key`; synchronous so the lock never spans an await
    private func inFlightTask(
        for key: NSString,
        orCreate make: () -> Task<UIImage?, Never>
    ) -> (task: Task<UIImage?, Never>, isCreator: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inFlight[key] { return (existing, false) }
        let task = make()
        inFlight[key] = task
        return (task, true)
    }

    private func clearInFlight(_ key: NSString) {
        lock.lock()
        defer { lock.unlock() }
        inFlight[key] = nil
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

/// A downsampling, decoded-cached replacement for `AsyncImage`
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    var grayscale: Bool = false
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        maxPixel: CGFloat,
        grayscale: Bool = false,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixel = maxPixel
        self.grayscale = grayscale
        self.placeholder = placeholder
        // seed from the cache at construction; .task fires after the first frame and would flash
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0, maxPixel: maxPixel) })
    }

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
            if image !== hit { image = hit }
            return
        }
        image = nil
        let loaded = await ImageCache.shared.load(url, maxPixel: maxPixel)
        if !Task.isCancelled {
            image = loaded
        }
    }
}
