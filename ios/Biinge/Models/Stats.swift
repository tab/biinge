import Foundation

struct AccountStats: Decodable, Sendable {
    let movies: Movies
    let series: Series
    let episodes: Episodes

    struct Movies: Decodable, Sendable {
        let want: Int
        let watched: Int
        let minutes: Int
    }

    struct Series: Decodable, Sendable {
        let want: Int
        let watching: Int
        let watched: Int
    }

    struct Episodes: Decodable, Sendable {
        let watched: Int
        let minutes: Int
    }
}
