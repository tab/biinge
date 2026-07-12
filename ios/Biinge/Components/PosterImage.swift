import SwiftUI

/// A 2:3 poster that loads from the TMDB image CDN, falling back to a gray card
/// with the title when there is no image — matching the RN app's Image behavior.
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
                if let url = Config.tmdbImageURL(path: path, size: size) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .empty:
                            ProgressView().tint(Color.biingeGrayDark)
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Text(title)
            .font(.biingeFootnote)
            .foregroundStyle(Color.biingeGrayDark)
            .multilineTextAlignment(.center)
            .padding(8)
    }
}
