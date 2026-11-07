import JellyfinAPI
import SwiftUI

/// A collection's screen: its name, overview and count over a paged poster grid of its movies and shows
struct DesktopCollectionView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let collection: BaseItemDto

    var body: some View {
        DesktopPagedGrid(
            connection: connection,
            list: .collection(collection.id ?? ""),
            minimumWidth: 160,
            empty: ("This collection is empty", "Add movies and shows to it on your Jellyfin server.")
        ) { _, total in
            VStack(alignment: .leading, spacing: 10) {
                Text("Collection")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(collection.name ?? "")
                    .font(.system(size: 56, weight: .bold))
                    .tracking(-2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let overview = collection.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 17))
                        .lineSpacing(4)
                        .lineLimit(3)
                        .opacity(0.78)
                        .frame(maxWidth: 640, alignment: .leading)
                }
                if let total {
                    Text(total == 1 ? "1 title" : "\(total) titles")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        } cell: { item in
            DesktopPosterCard(connection: connection, apiClient: apiClient, item: item)
        }
        .navigationTitle(collection.name ?? "")
    }
}
