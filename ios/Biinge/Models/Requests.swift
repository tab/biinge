import Foundation

/// Request bodies for library mutations and the watched-progress cascade.

struct CreateMovieBody: Encodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String
    let runtime: Int
    let state: String
}

struct UpdateMovieBody: Encodable, Sendable {
    let state: String
    let pinned: Bool
}

struct CreateSeriesBody: Encodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String
    let seasonsCount: Int
    let episodesCount: Int
    let status: String
    let state: String
}

struct UpdateSeriesBody: Encodable, Sendable {
    let state: String
    let pinned: Bool
}

struct UpdateAccountBody: Encodable, Sendable {
    let firstName: String
    let lastName: String
    let appearance: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case appearance
    }
}

// Progress payloads carry metadata so the server can materialize the
// series/season/episode rows it needs when marking items watched.

struct ProgressSeries: Encodable, Sendable {
    let title: String
    let posterPath: String
    let seasonsCount: Int
    let episodesCount: Int
    let status: String
}

struct ProgressEpisode: Encodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String
    let runtime: Int
    let airDate: String
}

struct ProgressSeasonMeta: Encodable, Sendable {
    let title: String
    let number: Int
    let episodesCount: Int
}

struct ProgressEpisodeMeta: Encodable, Sendable {
    let title: String
    let posterPath: String
    let runtime: Int
    let airDate: String
}

struct MarkSeasonBody: Encodable, Sendable {
    let series: ProgressSeries
    let season: ProgressSeasonMeta
    let episodes: [ProgressEpisode]
}

struct MarkEpisodeBody: Encodable, Sendable {
    let series: ProgressSeries
    let season: ProgressSeasonMeta
    let episode: ProgressEpisodeMeta
}
