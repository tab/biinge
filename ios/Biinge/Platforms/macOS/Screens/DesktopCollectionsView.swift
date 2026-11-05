import JellyfinAPI
import SwiftUI

/// Collections: the title and count over a paged grid of collection tiles
struct DesktopCollectionsView: View {
    let connection: JellyfinConnection

    var body: some View {
        DesktopPagedGrid(
            connection: connection,
            list: .collections,
            minimumWidth: 340,
            empty: ("No collections yet", "Group movies and shows into collections on your Jellyfin server.")
        ) { _, total in
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Collections")
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1.3)
                if let total {
                    Text(total == 1 ? "1 collection" : "\(total) collections")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
        } cell: { item in
            NavigationLink(value: DesktopRoute.collection(item)) {
                DesktopCollectionTile(connection: connection, collection: item)
            }
        }
        .navigationTitle("Collections")
    }
}
