import Foundation

/// Search and trending result items (camelCase JSON matches Swift names).

struct SearchMovie: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String
    let releaseDate: String?
    let rating: Double?
    let state: WatchState?
}

struct SearchSeries: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String
    let releaseDate: String?
    let rating: Double?
    let state: WatchState?
}

struct SearchPerson: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let profilePath: String
}
