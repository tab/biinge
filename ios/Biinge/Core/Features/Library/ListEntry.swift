import Foundation
import JellyfinAPI

/// The order of a biinge list (its raw value is what the iPhone remembers for each tab)
enum ListSort: String, Hashable {
    /// The store's order (pinned first, then newest added)
    case added
    case title

    /// The items in this order (by title ignoring case and with numbers by value, equal titles keeping the store's order)
    func sorted<Item>(_ items: [Item], title: (Item) -> String) -> [Item] {
        switch self {
        case .added: items
        // the standard library's sort is stable
        case .title: items.sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
        }
    }
}

/// A movie or a series on one of the user's biinge lists, as the list screens show it
struct ListEntry: Identifiable, Equatable {
    let title: DetailsTitle
    let name: String
    let posterPath: String
    let pinned: Bool
    /// The share of a series' episodes watched (nil for a movie)
    let progress: Double?
    /// The user's Jellyfin item for the title (nil unless exactly one library item matches)
    let jellyfinID: String?

    var id: DetailsTitle { title }

    /// Whether the poster shows the "Not on" note (never while Jellyfin is disconnected, when every poster shows plainly)
    func isOffServer(connected: Bool) -> Bool {
        connected && jellyfinID == nil
    }

    /// The played share of each item with a resume position, by Jellyfin item ID (from Jellyfin's resume list, so one call covers every poster)
    static func resumeShares(_ resumeItems: [BaseItemDto]) -> [String: Double] {
        var shares: [String: Double] = [:]
        for item in resumeItems {
            guard let id = item.id, (item.userData?.playbackPositionTicks ?? 0) > 0 else { continue }
            shares[id] = min(max((item.userData?.playedPercentage ?? 0) / 100, 0), 1)
        }
        return shares
    }

    /// The movies then the shows, in the store's order or by name
    static func entries(movies: [LibraryMovie], series: [LibrarySeries], sort: ListSort = .added) -> [ListEntry] {
        let entries = movies.map {
            ListEntry(title: .movie($0.id), name: $0.title, posterPath: $0.posterPath, pinned: $0.pinned, progress: nil, jellyfinID: $0.jellyfinID)
        } + series.map {
            ListEntry(title: .series($0.id), name: $0.title, posterPath: $0.posterPath, pinned: $0.pinned, progress: $0.progress, jellyfinID: $0.jellyfinID)
        }
        return sort.sorted(entries, title: \.name)
    }
}
