import SwiftUI
import ImageIO

/// Downsampling decoded-image cache so poster grids scroll smoothly within bounded memory
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    /// One decode per URL, the largest asked for so far, which a smaller ask reuses
    private let cache = NSCache<NSString, Decoded>()
    private let session: URLSession
    /// Coalesces concurrent loads of the same image at the same size into one download + decode
    private var inFlight: [NSString: Task<CGImage?, Never>] = [:]
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

    /// A decoded image with the downsample target it was decoded at
    private final class Decoded {
        let image: CGImage
        let maxPixel: CGFloat

        init(image: CGImage, maxPixel: CGFloat) {
            self.image = image
            self.maxPixel = maxPixel
        }
    }

    /// Synchronous cache peek so a scrolled-back cell shows instantly (no flash): the URL's decode at `maxPixel` or larger, so 0 takes any size
    func cached(_ url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let decoded = cache.object(forKey: url.absoluteString as NSString), decoded.maxPixel >= maxPixel else { return nil }
        return decoded.image
    }

    func load(_ url: URL, maxPixel: CGFloat) async -> CGImage? {
        if let hit = cached(url, maxPixel: maxPixel) { return hit }

        let cacheKey = url.absoluteString as NSString
        let flightKey = "\(url.absoluteString)#\(Int(maxPixel))" as NSString
        let (task, isCreator) = inFlightTask(for: flightKey) {
            Task { [session] () -> CGImage? in
                guard let (data, _) = try? await session.data(from: url) else { return nil }
                return Self.downsample(data, maxPixel: maxPixel)
            }
        }

        let image = await task.value
        // only the creator caches and unregisters, cache-before-clear so no request misses both
        if isCreator {
            // a smaller decode that lands after a larger one never replaces it, so the check and the write share the lock
            if let image {
                lock.withLock {
                    guard (cache.object(forKey: cacheKey)?.maxPixel ?? 0) < maxPixel else { return }
                    // Cost = decoded bitmap footprint, so totalCostLimit bounds real memory
                    let cost = image.bytesPerRow * image.height
                    cache.setObject(Decoded(image: image, maxPixel: maxPixel), forKey: cacheKey, cost: cost)
                }
            }
            clearInFlight(flightKey)
        }
        return image
    }

    /// Returns or registers the in-flight task for `key`; synchronous so the lock never spans an await
    private func inFlightTask(
        for key: NSString,
        orCreate make: () -> Task<CGImage?, Never>
    ) -> (task: Task<CGImage?, Never>, isCreator: Bool) {
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

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A downsampling, decoded-cached replacement for `AsyncImage`
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    var grayscale: Bool = false
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?
    /// Set once a load returns no image, which shows the placeholder even where loading shows nothing
    @State private var failed = false
    @Environment(\.posterFadeIndex) private var fadeIndex
    @Environment(\.imageLoadsClear) private var loadsClear
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // seed from any decode of the URL at construction, as .task fires after the first frame and would flash (a first layout can offer a size whose decode isn't cached yet)
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0, maxPixel: 0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(image, scale: 1, label: Text(""))
                    .resizable()
                    .scaledToFill()
                    .grayscale(grayscale ? 1 : 0)
                    // a poster's arrival grows from 97% as it fades in, over the placeholder fading out (Reduce Motion only fades)
                    .transition((fadeIndex == nil && !loadsClear) || reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            } else if loadsClear, url != nil, !failed {
                Color.clear
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
        // a smaller decode of this URL stays up while the sharper one loads, which then replaces it without a fade
        if let shown = image, shown === ImageCache.shared.cached(url, maxPixel: 0) {
            if let loaded = await ImageCache.shared.load(url, maxPixel: maxPixel), !Task.isCancelled { image = loaded }
            return
        }
        image = nil
        failed = false
        let loaded = await ImageCache.shared.load(url, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        guard fadeIndex != nil || loadsClear else {
            image = loaded
            failed = loaded == nil
            return
        }
        let delay = MotionDuration.posterFadeDelay(at: fadeIndex ?? 0, reduceMotion: reduceMotion)
        withAnimation(MotionCurve.standard.animation(MotionDuration.standard).delay(delay)) {
            image = loaded
            failed = loaded == nil
        }
    }
}

extension EnvironmentValues {
    /// The place of a poster in its grid or row, whose image then fades in on arrival 40 ms after the one before it (nil for an image that just appears)
    @Entry var posterFadeIndex: Int?
    /// Whether an image shows nothing while it loads and then grows in from 97% as it fades in (a details screen's hero art, whose background shows through; a failed or missing image still shows its placeholder)
    @Entry var imageLoadsClear = false
}
