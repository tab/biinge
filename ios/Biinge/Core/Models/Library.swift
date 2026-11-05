import Foundation

/// Library resources use camelCase JSON matching Swift property names, so only jellyfinId needs a CodingKey

/// The shared state vocabulary: movies use want/watched, series add watching, games use want/playing/played
enum WatchState: String, Codable, Sendable {
    case want
    case watching
    case watched
    case playing
    case played
    case none
}

struct LibraryMovie: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let title: String
    let posterPath: String
    let pinned: Bool
    let state: WatchState
    /// The user's Jellyfin item for this movie (nil unless exactly one library item matches)
    let jellyfinID: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, posterPath, pinned, state
        case jellyfinID = "jellyfinId"
    }
}

struct LibrarySeries: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let title: String
    let posterPath: String
    let pinned: Bool
    let state: WatchState
    let episodesCount: Int
    let watchedEpisodesCount: Int
    /// The user's Jellyfin item for this series (nil unless exactly one library item matches)
    let jellyfinID: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, posterPath, pinned, state, episodesCount, watchedEpisodesCount
        case jellyfinID = "jellyfinId"
    }

    /// Share of episodes watched across all seasons, clamped to 0...1
    var progress: Double {
        guard episodesCount > 0 else { return 0 }
        return min(Double(watchedEpisodesCount) / Double(episodesCount), 1)
    }
}

/// posterPath is an IGDB cover image_id, not a path
struct LibraryGame: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let title: String
    let posterPath: String
    let pinned: Bool
    let state: WatchState
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
