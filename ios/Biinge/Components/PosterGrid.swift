import SwiftUI

/// A scrolling two-column grid of poster cells (4:6 posters, matching the RN grid).
struct PosterGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder let cell: (Item) -> Cell

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    cell(item)
                }
            }
            .padding(8)
        }
    }
}
