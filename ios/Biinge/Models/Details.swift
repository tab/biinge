import Foundation

/// TMDB-sourced detail resources (camelCase JSON matches Swift names).

struct CreditPerson: Decodable, Sendable, Identifiable {
    let id: Int
    let profilePath: String
    let name: String
    let description: String
}

struct Recommendation: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String
    let state: WatchState?
}

struct Video: Decodable, Sendable, Identifiable {
    let id: String
    let key: String
}

struct MovieDetails: Decodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String
    let pinned: Bool
    let state: WatchState
    let overview: String
    let status: String?
    let releaseDate: String?
    let runtime: Int?
    let rating: Double?
    let credits: [CreditPerson]
    let recommendations: [Recommendation]
    let videos: [Video]
}

struct SeasonSummary: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let number: Int
    let posterPath: String
    let episodesCount: Int
    let airDate: String?
}

struct SeriesDetails: Decodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String
    let pinned: Bool
    let state: WatchState
    let overview: String
    let status: String?
    let releaseDate: String?
    let seasonsCount: Int?
    let episodesCount: Int?
    let rating: Double?
    let credits: [CreditPerson]
    let recommendations: [Recommendation]
    let videos: [Video]
    let seasons: [SeasonSummary]
}

struct EpisodeSummary: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let number: Int
    let posterPath: String
    let runtime: Int
    let overview: String
    let rating: Double?
    let airDate: String?
}

struct SeasonDetails: Decodable, Sendable {
    let id: Int
    let title: String
    let number: Int
    let posterPath: String
    let airDate: String?
    let overview: String
    let episodes: [EpisodeSummary]
}

struct EpisodeDetails: Decodable, Sendable {
    let id: Int
    let title: String
    let number: Int
    let posterPath: String
    let runtime: Int
    let overview: String
    let rating: Double?
    let airDate: String?
    let credits: [CreditPerson]
    let videos: [Video]
}

struct MovieCredit: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String
    let state: WatchState?
    let type: String?
}

struct PersonDetails: Decodable, Sendable {
    let id: Int
    let name: String
    let birthday: String?
    let profilePath: String
    let gender: Int
    let movieCredits: [MovieCredit]
}

/// Per-show watched progress (ids of watched seasons/episodes).
struct WatchProgress: Decodable, Sendable {
    let id: Int
    let state: WatchState
    let watchedSeasons: [Int]
    let watchedEpisodes: [Int]
}
