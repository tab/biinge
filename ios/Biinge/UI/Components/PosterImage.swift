import SwiftUI

/// A 2:3 poster with a gray title-card fallback, from the TMDB or the IGDB image CDN
struct PosterImage: View {
    /// Which CDN `path` addresses: a TMDB poster path, or an IGDB cover image_id
    enum Source {
        case tmdb
        case igdb
    }

    let path: String
    let title: String
    var source: Source = .tmdb
    var size: String = "w342"
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.biingeSecondaryCard)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                CachedImage(url: url, maxPixel: Self.maxPixel(for: size)) {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var url: URL? {
        switch source {
        case .tmdb: Config.tmdbImageURL(path: path, size: size)
        case .igdb: Config.igdbImageURL(imageId: path, size: size)
        }
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
            .font(.biingeFootnote)
            .foregroundStyle(Color.biingeGrayDark)
            .multilineTextAlignment(.center)
            .padding(8)
    }
}
