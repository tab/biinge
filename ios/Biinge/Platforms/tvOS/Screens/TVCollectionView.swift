import JellyfinAPI
import SwiftUI

/// A collection's screen: fanned posters, name, overview and count over a paged grid of its movies and shows
struct TVCollectionView: View {
    let connection: JellyfinConnection
    let collection: BaseItemDto

    var body: some View {
        TVPagedGrid(
            connection: connection,
            list: .collection(collection.id ?? ""),
            columns: 6,
            columnWidth: 260,
            empty: ("This collection is empty", "Add movies and shows to it on your Jellyfin server.")
        ) { items, total in
            HStack(alignment: .bottom, spacing: 64) {
                fan(items.prefix(3).map { connection.posterURL($0, maxWidth: 380) })
                VStack(alignment: .leading, spacing: 16) {
                    Text("Collection")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(Color.biingeText.opacity(0.72))
                    Text(collection.name ?? "")
                        .font(.system(size: 100, weight: .bold))
                        .tracking(100 * -0.035)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let overview = collection.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 30))
                            .lineSpacing(7)
                            .lineLimit(3)
                            .foregroundStyle(Color.biingeText.opacity(0.78))
                            .frame(maxWidth: 1100, alignment: .leading)
                    }
                    Text(total == 1 ? "1 title" : "\(total) titles")
                        .font(.system(size: 27))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                        .padding(.top, 8)
                }
            }
        } cell: { item in
            TVPosterCard(connection: connection, item: item)
        }
    }

    /// The mockup's fan: the second poster in the centre, the first tilted left and the third (or the first) tilted right
    private func fan(_ posters: [URL?]) -> some View {
        let center = posters.count > 1 ? posters[1] : posters.isEmpty ? nil : posters[0]
        let left = posters.count > 1 ? posters[0] : nil
        let right = posters.count > 2 ? posters[2] : left
        return ZStack(alignment: .topLeading) {
            if posters.count > 1 {
                PosterImage(title: "", cornerRadius: 0, poster: left, frame: CGSize(width: 180, height: 270), titleFont: .system(size: 26), titlePadding: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .rotationEffect(.degrees(-9))
                    .shadow(color: Color.biingeShadow.opacity(0.5), radius: 25, y: 22)
                    .offset(y: 36)
                PosterImage(title: "", cornerRadius: 0, poster: right, frame: CGSize(width: 180, height: 270), titleFont: .system(size: 26), titlePadding: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .rotationEffect(.degrees(9))
                    .shadow(color: Color.biingeShadow.opacity(0.5), radius: 25, y: 22)
                    .offset(x: 223, y: 36)
            }
            PosterImage(title: "", cornerRadius: 0, poster: center, frame: CGSize(width: 191, height: 286), titleFont: .system(size: 26), titlePadding: 20)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.biingeShadow.opacity(0.6), radius: 30, y: 28)
                .offset(x: 108, y: 7)
        }
        .frame(width: 410, height: 317, alignment: .topLeading)
    }
}
