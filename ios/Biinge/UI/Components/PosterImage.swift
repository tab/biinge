import SwiftUI

/// A 2:3 poster with a gray title-card fallback, from the TMDB or the IGDB image CDN
struct PosterImage: View {
    /// Which CDN `path` addresses: a TMDB poster path, or an IGDB cover image_id
    enum Source {
        case tmdb
        case igdb
    }

    var path = ""
    let title: String
    var source: Source = .tmdb
    var size: String = "w342"
    var cornerRadius: CGFloat = 12
    /// An image shown in place of `path`'s (the Jellyfin poster a details screen opened from)
    var poster: URL?
    /// The size the art fills, in place of a 2:3 fit to the offered width (Mac and Apple TV artwork, decoded at `maxPixel(fitting:)`)
    var frame: CGSize?
    var titleFont: Font = .biingeFootnote
    var titlePadding: CGFloat = 8

    @Environment(\.imageLoadsClear) private var loadsClear

    var body: some View {
        // the card fill stays out of a slot that shows nothing while it loads, and its placeholder brings the fill
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(loadsClear ? Color.clear : Color.biingeSecondaryCard)
            // a fixed frame keeps its own size, as the 2:3 fit around it only changes what it is offered
            .frame(width: frame?.width, height: frame?.height)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                CachedImage(url: url, maxPixel: frame.map(Self.maxPixel(fitting:)) ?? Self.maxPixel(for: size)) {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var url: URL? {
        if let poster { return poster }
        return switch source {
        case .tmdb: Config.tmdbImageURL(path: path, size: size)
        case .igdb: Config.igdbImageURL(imageId: path, size: size)
        }
    }

    /// Downsample target of a fixed frame: twice its longer side, rounded up to 100 px so a slightly resized Mac window reuses the posters already decoded
    static func maxPixel(fitting frame: CGSize) -> CGFloat {
        (max(frame.width, frame.height) * 2 / 100).rounded(.up) * 100
    }

    /// Downsample target per source width (TMDB w-sizes, then IGDB t-sizes)
    private static func maxPixel(for size: String) -> CGFloat {
        switch size {
        case "w185": return 400
        case "w500": return 1000
        case "w780": return 1200
        case "cover_big": return 300
        case "cover_big_2x": return 600
        case "1080p": return 800
        default: return 700
        }
    }

    private var placeholder: some View {
        Text(title)
            .font(titleFont)
            .foregroundStyle(Color.biingeGrayDark)
            .multilineTextAlignment(.center)
            .padding(titlePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // a grid poster's fill sits under the image already, so only the clear slot's fallback brings its own
            .background(loadsClear ? Color.biingeSecondaryCard : .clear)
    }
}
