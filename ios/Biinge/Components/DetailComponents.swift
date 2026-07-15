import SwiftUI

extension View {
    /// Rounded-top card backing for detail sheets; bleeds card color through the bottom safe area
    func detailCardBackground() -> some View {
        background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .fill(Color.biingeCard)
                .ignoresSafeArea(edges: .bottom)
        )
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
                CachedImage(url: Config.tmdbImageURL(path: path, size: "w185"), maxPixel: 300, grayscale: grayscale) {
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
            LazyHStack(alignment: .top, spacing: 12) {
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
