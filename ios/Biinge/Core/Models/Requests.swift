import Foundation

/// Request bodies for library mutations and the watched-progress cascade

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

struct CreateGameBody: Encodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String
    let runtime: Int
    let state: String
}

struct UpdateGameBody: Encodable, Sendable {
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

/// The Jellyfin username and password the API signs in with once (it never stores the password)
struct JellyfinConnectionRequest: Encodable, Sendable {
    let username: String
    let password: String
}

// Progress payloads carry metadata so the server can materialize series/season/episode rows

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

/// A season with its episodes, inside a whole-show mark
struct ProgressSeason: Encodable, Sendable {
    let id: Int
    let title: String
    let number: Int
    let episodesCount: Int
    let episodes: [ProgressEpisode]
}

struct MarkSeriesBody: Encodable, Sendable {
    let series: ProgressSeries
    let seasons: [ProgressSeason]
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
