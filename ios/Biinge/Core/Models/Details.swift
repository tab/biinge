import Foundation

/// TMDB-sourced detail resources (camelCase JSON matches Swift names)

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

/// IGDB-sourced game detail; runtime is minutes to beat normally, runtimeCompleted minutes to reach 100%
struct GameDetails: Decodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String
    let pinned: Bool
    let state: WatchState
    let overview: String
    let status: String?
    let releaseDate: String?
    let runtime: Int?
    let runtimeCompleted: Int?
    let rating: Double?
    let genres: [String]
    let platforms: [String]
    let recommendations: [Recommendation]

    private enum CodingKeys: String, CodingKey {
        case id, title, posterPath, pinned, state, overview, status, releaseDate
        case runtime, runtimeCompleted, rating, genres, platforms, recommendations
    }

    // recommendations default to empty so an API that predates the field still decodes
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        posterPath = try c.decode(String.self, forKey: .posterPath)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        state = try c.decode(WatchState.self, forKey: .state)
        overview = try c.decode(String.self, forKey: .overview)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        runtime = try c.decodeIfPresent(Int.self, forKey: .runtime)
        runtimeCompleted = try c.decodeIfPresent(Int.self, forKey: .runtimeCompleted)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        genres = try c.decode([String].self, forKey: .genres)
        platforms = try c.decode([String].self, forKey: .platforms)
        recommendations = try c.decodeIfPresent([Recommendation].self, forKey: .recommendations) ?? []
    }
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

extension SeriesDetails {
    /// Regular-season count (excluding specials), preferring the server value over the loaded seasons
    var regularSeasonsCount: Int {
        seasonsCount ?? seasons.filter { $0.number > 0 }.count
    }

    /// Total episode count, preferring the server value over summing the loaded seasons
    var totalEpisodesCount: Int {
        episodesCount ?? seasons.reduce(0) { $0 + $1.episodesCount }
    }
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
    let watched: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, number, posterPath, runtime, overview, rating, airDate, watched
    }

    // watched defaults to false so an API that predates the field still decodes
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        number = try c.decode(Int.self, forKey: .number)
        posterPath = try c.decode(String.self, forKey: .posterPath)
        runtime = try c.decode(Int.self, forKey: .runtime)
        overview = try c.decode(String.self, forKey: .overview)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        airDate = try c.decodeIfPresent(String.self, forKey: .airDate)
        watched = try c.decodeIfPresent(Bool.self, forKey: .watched) ?? false
    }
}

struct SeasonDetails: Decodable, Sendable {
    let id: Int
    let title: String
    let number: Int
    let posterPath: String
    let airDate: String?
    let overview: String
    let watched: Bool
    let episodes: [EpisodeSummary]

    private enum CodingKeys: String, CodingKey {
        case id, title, number, posterPath, airDate, overview, watched, episodes
    }

    // watched defaults to false so an API that predates the field still decodes
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        number = try c.decode(Int.self, forKey: .number)
        posterPath = try c.decode(String.self, forKey: .posterPath)
        airDate = try c.decodeIfPresent(String.self, forKey: .airDate)
        overview = try c.decode(String.self, forKey: .overview)
        watched = try c.decodeIfPresent(Bool.self, forKey: .watched) ?? false
        episodes = try c.decode([EpisodeSummary].self, forKey: .episodes)
    }
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
    let watched: Bool
    let credits: [CreditPerson]
    let videos: [Video]

    private enum CodingKeys: String, CodingKey {
        case id, title, number, posterPath, runtime, overview, rating, airDate, watched, credits, videos
    }

    // watched defaults to false so an API that predates the field still decodes
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        number = try c.decode(Int.self, forKey: .number)
        posterPath = try c.decode(String.self, forKey: .posterPath)
        runtime = try c.decode(Int.self, forKey: .runtime)
        overview = try c.decode(String.self, forKey: .overview)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        airDate = try c.decodeIfPresent(String.self, forKey: .airDate)
        watched = try c.decodeIfPresent(Bool.self, forKey: .watched) ?? false
        credits = try c.decode([CreditPerson].self, forKey: .credits)
        videos = try c.decode([Video].self, forKey: .videos)
    }
}

struct MovieCredit: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String
    let state: WatchState?
    let type: String?
}

struct TvCredit: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String
    let state: WatchState?
}

struct PersonDetails: Decodable, Sendable {
    let id: Int
    let name: String
    let birthday: String?
    let profilePath: String
    let gender: Int
    let movieCredits: [MovieCredit]
    let tvCredits: [TvCredit]

    private enum CodingKeys: String, CodingKey {
        case id, name, birthday, profilePath, gender, movieCredits, tvCredits
    }

    // Credits default to empty so an API without tvCredits (not yet deployed) still decodes
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        birthday = try container.decodeIfPresent(String.self, forKey: .birthday)
        profilePath = try container.decode(String.self, forKey: .profilePath)
        gender = try container.decode(Int.self, forKey: .gender)
        movieCredits = try container.decodeIfPresent([MovieCredit].self, forKey: .movieCredits) ?? []
        tvCredits = try container.decodeIfPresent([TvCredit].self, forKey: .tvCredits) ?? []
    }
}

/// Per-show watched progress; trackedState is the user's explicit choice that unmark-all reverts to
struct WatchProgress: Decodable, Sendable {
    let id: Int
    let state: WatchState
    let trackedState: WatchState?
    let watchedSeasons: [Int]
    let watchedEpisodes: [Int]
}

// MARK: - Optimistic mutations

/// Local approximations of the server's derived progress, replaced by the server response
extension WatchProgress {
    /// TMDB status of a show still airing; never derived "watched" (mirrors the server)
    static let tvInProductionStatus = "Returning Series"

    /// Progress after toggling one episode; a known `seasonEpisodes` list also flips season completeness
    func togglingEpisode(
        id episodeId: Int,
        watched: Bool,
        seasonId: Int,
        seasonEpisodes: [EpisodeSummary] = [],
        totalSeasons: Int? = nil,
        showStatus: String? = nil
    ) -> WatchProgress {
        var episodes = Set(watchedEpisodes)
        var seasons = Set(watchedSeasons)
        if watched {
            episodes.insert(episodeId)
            if !seasonEpisodes.isEmpty, seasonEpisodes.allSatisfy({ episodes.contains($0.id) }) {
                seasons.insert(seasonId)
            }
        } else {
            episodes.remove(episodeId)
            seasons.remove(seasonId)
        }
        return replacing(seasons: seasons, episodes: episodes, totalSeasons: totalSeasons, showStatus: showStatus)
    }

    /// Progress after marking/unmarking a whole season
    func togglingSeason(
        id seasonId: Int,
        episodeIds: [Int],
        watched: Bool,
        totalSeasons: Int? = nil,
        showStatus: String? = nil
    ) -> WatchProgress {
        var episodes = Set(watchedEpisodes)
        var seasons = Set(watchedSeasons)
        if watched {
            episodes.formUnion(episodeIds)
            seasons.insert(seasonId)
        } else {
            episodes.subtract(episodeIds)
            seasons.remove(seasonId)
        }
        return replacing(seasons: seasons, episodes: episodes, totalSeasons: totalSeasons, showStatus: showStatus)
    }

    private func replacing(seasons: Set<Int>, episodes: Set<Int>, totalSeasons: Int?, showStatus: String?) -> WatchProgress {
        WatchProgress(
            id: id,
            state: derivedState(
                watchedEpisodesCount: episodes.count,
                watchedSeasonsCount: seasons.count,
                totalSeasons: totalSeasons,
                status: showStatus
            ),
            trackedState: trackedState,
            watchedSeasons: Array(seasons),
            watchedEpisodes: Array(episodes)
        )
    }

    /// Mirrors the server's deriveSeriesState: watched once every regular season is watched, not by episode totals
    private func derivedState(watchedEpisodesCount: Int, watchedSeasonsCount: Int, totalSeasons: Int?, status: String?) -> WatchState {
        if watchedEpisodesCount == 0 { return trackedState ?? .none }
        if let totalSeasons, totalSeasons > 0, watchedSeasonsCount >= totalSeasons, status != Self.tvInProductionStatus {
            return .watched
        }
        return .watching
    }
}
