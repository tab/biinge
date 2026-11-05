import SwiftUI

/// The Collections tab: the title and count over a paged grid of collection tiles
struct TVCollectionsView: View {
    let connection: JellyfinConnection

    var body: some View {
        // three 640-point tiles don't fit the 1920-point screen, so the grid's tiles are 560 by 315
        TVPagedGrid(
            connection: connection,
            list: .collections,
            columns: 3,
            columnWidth: 560,
            // a focused tile grows 28 points a side, so the wider gap keeps it clear of its neighbours
            columnSpacing: 48,
            empty: ("No collections yet", "Group movies and shows into collections on your Jellyfin server.")
        ) { _, total in
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text("Collections")
                    .font(.system(size: 76, weight: .bold))
                    .tracking(76 * -0.03)
                Text(total == 1 ? "1 collection" : "\(total) collections")
                    .font(.system(size: 29))
                    .foregroundStyle(Color.biingeText.opacity(0.55))
            }
        } cell: { item in
            NavigationLink(value: TVRoute.collection(item)) {
                TVCollectionTile(connection: connection, collection: item, width: 560, height: 315)
            }
            .buttonStyle(TVCardButtonStyle(width: 560, height: 315, cornerRadius: 20, title: nil, subtitle: nil))
        }
    }
}
