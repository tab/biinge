import SwiftUI

/// A 2:3 poster from the TMDB image CDN with a gray title-card fallback
struct PosterImage: View {
    let path: String
    let title: String
    var size: String = "w342"
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.biingeSecondaryCard)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                CachedImage(url: Config.tmdbImageURL(path: path, size: size), maxPixel: Self.maxPixel(for: size)) {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Downsample target per TMDB source width
    private static func maxPixel(for size: String) -> CGFloat {
        switch size {
        case "w185": return 400
        case "w500": return 1000
        case "w780": return 1200
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
