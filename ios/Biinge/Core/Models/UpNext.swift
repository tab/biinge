import Foundation

/// The user's ready-to-watch queue: aired episodes, released movies and released games from pinned library items
struct UpNext: Decodable, Sendable {
    let episodes: [UpNextEpisode]
    let movies: [UpNextMovie]
    let games: [UpNextGame]

    private enum CodingKeys: String, CodingKey {
        case episodes, movies, games
    }

    // every list defaults to empty so an API that predates the endpoint, or the games in it, still decodes
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        episodes = try c.decodeIfPresent([UpNextEpisode].self, forKey: .episodes) ?? []
        movies = try c.decodeIfPresent([UpNextMovie].self, forKey: .movies) ?? []
        games = try c.decodeIfPresent([UpNextGame].self, forKey: .games) ?? []
    }

    var isEmpty: Bool { episodes.isEmpty && movies.isEmpty && games.isEmpty }
}

/// One aired episode carrying the show context needed to open its detail sheet
struct UpNextEpisode: Decodable, Sendable, Identifiable {
    let seriesId: Int
    let seriesTitle: String
    let seriesPosterPath: String
    let id: Int
    let title: String
    let seasonNumber: Int
    let number: Int
    let posterPath: String
    let overview: String
    let runtime: Int
    let rating: Double?
    let airDate: String

    private enum CodingKeys: String, CodingKey {
        case seriesId, seriesTitle, seriesPosterPath, id, title, seasonNumber, number, posterPath, overview, runtime, rating, airDate
    }

    // display fields default so a leaner payload still decodes; ids the client needs to open the episode are required
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seriesId = try c.decode(Int.self, forKey: .seriesId)
        seriesTitle = try c.decodeIfPresent(String.self, forKey: .seriesTitle) ?? ""
        seriesPosterPath = try c.decodeIfPresent(String.self, forKey: .seriesPosterPath) ?? ""
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        seasonNumber = try c.decode(Int.self, forKey: .seasonNumber)
        number = try c.decode(Int.self, forKey: .number)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath) ?? ""
        overview = try c.decodeIfPresent(String.self, forKey: .overview) ?? ""
        runtime = try c.decodeIfPresent(Int.self, forKey: .runtime) ?? 0
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        airDate = try c.decodeIfPresent(String.self, forKey: .airDate) ?? ""
    }
}

/// One released game from the user's pinned want list (posterPath is an IGDB cover id, runtime the time to beat)
struct UpNextGame: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String
    let overview: String
    let runtime: Int
    let rating: Double?
    let releaseDate: String

    private enum CodingKeys: String, CodingKey {
        case id, title, posterPath, overview, runtime, rating, releaseDate
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath) ?? ""
        overview = try c.decodeIfPresent(String.self, forKey: .overview) ?? ""
        runtime = try c.decodeIfPresent(Int.self, forKey: .runtime) ?? 0
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
    }
}

/// One released movie from the user's pinned want list
struct UpNextMovie: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String
    let overview: String
    let runtime: Int
    let rating: Double?
    let releaseDate: String

    private enum CodingKeys: String, CodingKey {
        case id, title, posterPath, overview, runtime, rating, releaseDate
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath) ?? ""
        overview = try c.decodeIfPresent(String.self, forKey: .overview) ?? ""
        runtime = try c.decodeIfPresent(Int.self, forKey: .runtime) ?? 0
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
    }
}
