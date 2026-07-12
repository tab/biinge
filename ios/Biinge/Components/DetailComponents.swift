import SwiftUI

struct RatingView: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.biingePrimary)
            Text(String(format: "%.1f", rating))
                .font(.biingeCaption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ProfileCircle: View {
    let path: String
    var size: CGFloat = 64
    var grayscale: Bool = false

    var body: some View {
        Circle()
            .fill(Color.biingeSecondaryCard)
            .frame(width: size, height: size)
            .overlay {
                if let url = Config.tmdbImageURL(path: path, size: "w185") {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill().grayscale(grayscale ? 1 : 0)
                    } placeholder: {
                        Image(systemName: "person.fill").foregroundStyle(Color.biingeGrayDark)
                    }
                } else {
                    Image(systemName: "person.fill").foregroundStyle(Color.biingeGrayDark)
                }
            }
            .clipShape(Circle())
    }
}

struct CreditsRow: View {
    let credits: [CreditPerson]
    @Environment(\.presentPerson) private var presentPerson

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(credits) { person in
                    Button {
                        presentPerson(person.id)
                    } label: {
                        VStack(spacing: 6) {
                            ProfileCircle(path: person.profilePath, grayscale: true)
                            Text(person.name)
                                .font(.biingeCaption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(person.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 78)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct TrailerButton: View {
    let videoKey: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        ActionButton(title: "Trailer", systemImage: "play.fill", isActive: false) {
            if let url = URL(string: "https://www.youtube.com/watch?v=\(videoKey)") {
                openURL(url)
            }
        }
    }
}

/// A compact vertical icon+label action used in a detail screen's action row.
struct ActionButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 20))
                Text(title).font(.biingeCaption2)
            }
            .foregroundStyle(isActive ? .black : Color.biingeText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isActive ? Color.biingePrimary : Color.biingeSecondaryCard,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.biingeSubhead)
                .foregroundStyle(.primary)
                .padding(.horizontal)
            content
        }
    }
}
