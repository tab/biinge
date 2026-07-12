import Foundation

/// Library resources use camelCase JSON that already matches Swift property
/// names, so no CodingKeys are needed.

enum WatchState: String, Codable, Sendable {
    case want
    case watching
    case watched
    case none
}

struct LibraryMovie: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let title: String
    let posterPath: String
    let pinned: Bool
    let state: WatchState
}

struct LibrarySeries: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let title: String
    let posterPath: String
    let pinned: Bool
    let state: WatchState
    let episodesCount: Int
    let watchedEpisodesCount: Int

    /// Share of episodes watched across all seasons, clamped to 0...1.
    var progress: Double {
        guard episodesCount > 0 else { return 0 }
        return min(Double(watchedEpisodesCount) / Double(episodesCount), 1)
    }
}

struct Paginated<Element: Decodable & Sendable>: Decodable, Sendable {
    let data: [Element]
    let meta: Meta

    struct Meta: Decodable, Sendable {
        let page: Int
        let per: Int
        let total: Int
    }
}
