import Foundation

struct AccountStats: Decodable, Sendable {
    let movies: Movies
    let series: Series
    let episodes: Episodes
    // optional so a stats payload without activity (older API) still decodes
    let activity: [Monthly]?

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

    /// Watched runtime for one calendar month, split by media kind
    struct Monthly: Decodable, Sendable, Identifiable {
        let month: String
        let movieMinutes: Int
        let tvMinutes: Int

        var id: String { month }
        var totalMinutes: Int { movieMinutes + tvMinutes }

        /// First day of the month parsed from the "yyyy-MM" key
        var date: Date {
            let parts = month.split(separator: "-")
            guard parts.count == 2, let year = Int(parts[0]), let monthValue = Int(parts[1]) else {
                return .distantPast
            }
            var components = DateComponents()
            components.year = year
            components.month = monthValue
            components.day = 1
            return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
        }
    }
}
