import Foundation

/// Calendar period the statistics screen aggregates watched activity over
enum StatsPeriod: String, Sendable, CaseIterable {
    case week, month, year, all

    /// Chip label
    var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .all: return "All"
        }
    }

    /// Calendar unit the API buckets this period's activity by
    var unit: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .year: return .month
        case .all: return .year
        }
    }

    /// Label for the want bar, which counts additions rather than the whole list on a bounded period
    var wantLabel: String {
        self == .all ? "Want" : "Added"
    }

    /// Trailing phrase naming the period in captions
    var phrase: String {
        switch self {
        case .week: return "this week"
        case .month: return "this month"
        case .year: return "this year"
        case .all: return "all time"
        }
    }
}

struct AccountStats: Decodable, Sendable {
    let movies: Movies
    let series: Series
    let episodes: Episodes
    // optional so a stats payload without activity or games (older API) still decodes
    let activity: [Bucket]?
    let games: Games?

    /// want is the whole list all-time, and what was added to it inside a bounded period
    struct Movies: Decodable, Sendable {
        let want: Int
        let watched: Int
        let minutes: Int
    }

    /// watched is finished shows all-time, and shows with an episode watched inside a bounded period
    struct Series: Decodable, Sendable {
        let want: Int
        // a show is being watched now, so no bounded period carries this
        let watching: Int?
        let watched: Int
    }

    struct Episodes: Decodable, Sendable {
        let watched: Int
        let minutes: Int
    }

    /// played is games finished all-time, and games finished inside a bounded period.
    /// minutes is IGDB's time to beat those games, not time the user actually played
    struct Games: Decodable, Sendable {
        let want: Int
        // a game is being played now, so no bounded period carries this
        let playing: Int?
        let played: Int
        let minutes: Int
    }

    /// Watched runtime for one activity bucket, split by media kind
    struct Bucket: Decodable, Sendable, Identifiable {
        let date: String
        let movieMinutes: Int
        let tvMinutes: Int

        var id: String { date }
        var totalMinutes: Int { movieMinutes + tvMinutes }

        /// Start of the bucket parsed from the "yyyy-MM-dd" key
        var start: Date {
            let parts = date.split(separator: "-")
            guard parts.count == 3,
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
                return .distantPast
            }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
        }
    }
}
