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

    /// Label for the want bar, which counts additions rather than the whole list on a bounded period
    var wantLabel: String {
        self == .all ? "Want" : "Added"
    }

    /// Range line over the hero total ("This week", "This month", the year, "All time")
    func range(now: Date, calendar: Calendar = .current) -> String {
        switch self {
        case .week: return "This week"
        case .month: return "This month"
        case .year:
            // the API keys its buckets by gregorian year, whichever calendar the user reads dates in
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            return String(gregorian.component(.year, from: now))
        case .all: return "All time"
        }
    }

    /// Names the bucket starting at `start` above the chart ("Today", "Saturday, Oct 31", "July", "November so far", "2026 so far")
    func calloutLabel(for start: Date, now: Date, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        switch self {
        case .week, .month:
            return calendar.isDate(start, inSameDayAs: now) ? "Today" : start.formatted(style.weekday(.wide).month(.abbreviated).day())
        case .year:
            let name = start.formatted(style.month(.wide))
            return calendar.isDate(start, equalTo: now, toGranularity: .month) ? "\(name) so far" : name
        case .all:
            // the API keys its buckets by gregorian year, whichever calendar the user reads dates in
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            let name = String(gregorian.component(.year, from: start))
            return gregorian.isDate(start, equalTo: now, toGranularity: .year) ? "\(name) so far" : name
        }
    }

    /// Label under bar `index` (narrow weekdays, every 7th day with the first as "Nov 1", narrow months, years as ’19), empty where a bar goes unlabelled
    func axisLabel(at index: Int, of buckets: [AccountStats.Bucket], calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        let start = buckets[index].start
        switch self {
        case .week:
            return start.formatted(style.weekday(.narrow))
        case .month:
            guard index.isMultiple(of: 7) else { return "" }
            return index == 0 ? start.formatted(style.month(.abbreviated).day()) : String(calendar.component(.day, from: start))
        case .year:
            return start.formatted(style.month(.narrow))
        case .all:
            // a long history labels every nth year, so no more than eight labels share the row
            guard index.isMultiple(of: (buckets.count + 7) / 8) else { return "" }
            // the API keys its buckets by gregorian year, whichever calendar the user reads dates in
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            return String(format: "’%02d", gregorian.component(.year, from: start) % 100)
        }
    }

    /// Highlight tiles under the chart: a streak (week and month only), the busiest bucket, episodes and the daily average
    func highlights(for stats: AccountStats, now: Date, calendar: Calendar = .current) -> [StatsHighlight] {
        let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        let buckets = stats.activity ?? []
        var tiles: [StatsHighlight] = []

        switch self {
        case .week:
            let days = AccountStats.currentStreak(buckets, now: now, calendar: calendar)
            tiles.append(StatsHighlight(symbol: "flame", value: days == 1 ? "1 day" : "\(days) days", label: "Current streak"))
        case .month:
            let days = AccountStats.longestStreak(buckets)
            tiles.append(StatsHighlight(symbol: "flame", value: days == 1 ? "1 day" : "\(days) days", label: "Longest streak"))
        case .year, .all:
            break
        }

        if let peak = AccountStats.peakIndex(buckets) {
            let start = buckets[peak].start
            // the API keys its buckets by gregorian year, whichever calendar the user reads dates in
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            let name = switch self {
            case .week, .month: start.formatted(style.weekday(.wide))
            case .year: start.formatted(style.month(.wide))
            case .all: String(gregorian.component(.year, from: start))
            }
            let label = switch self {
            case .week, .month: "Busiest day"
            case .year: "Busiest month"
            case .all: "Busiest year"
            }
            tiles.append(StatsHighlight(symbol: "calendar", value: buckets[peak].totalMinutes > 0 ? name : "None", label: label))
        }

        let episodes = stats.episodes.watched.formatted(.number.locale(calendar.locale ?? .current))
        tiles.append(StatsHighlight(symbol: "tv", value: episodes, label: "Episodes"))

        if let average = AccountStats.dailyAverage(stats.totalMinutes, buckets: buckets, now: now, calendar: calendar) {
            let value = average < 60 ? "\(average) min" : AccountStats.duration(average)
            tiles.append(StatsHighlight(symbol: "clock", value: value, label: "Daily average"))
        }
        return tiles
    }
}

/// One number of a duration and its unit letter (the hero draws the two at different sizes)
struct DurationPart: Equatable, Sendable {
    let value: Int
    let unit: String
}

/// One highlight tile under the activity chart
struct StatsHighlight: Equatable, Sendable {
    let symbol: String
    let value: String
    let label: String
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
        let seriesMinutes: Int

        var id: String { date }
        var totalMinutes: Int { movieMinutes + seriesMinutes }

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

extension AccountStats {
    /// Watched runtime across movies and episodes
    var totalMinutes: Int { movies.minutes + episodes.minutes }

    /// Movies' rounded share of the watched runtime in percent (0 when nothing was watched)
    var moviePercent: Int {
        totalMinutes > 0 ? Int((Double(movies.minutes) / Double(totalMinutes) * 100).rounded()) : 0
    }

    /// TV's share, the rest of 100 so the two legend figures always add up (0 when nothing was watched)
    var seriesPercent: Int {
        totalMinutes > 0 ? 100 - moviePercent : 0
    }

    /// Splits a runtime into parts (under an hour "42m", under a day "5h 12m", else "1w 2d 3h" rounded to the hour)
    static func durationParts(_ minutes: Int) -> [DurationPart] {
        if minutes == 0 { return [DurationPart(value: 0, unit: "h")] }
        if minutes < 60 { return [DurationPart(value: minutes, unit: "m")] }
        if minutes < 24 * 60 {
            let hours = DurationPart(value: minutes / 60, unit: "h")
            return minutes % 60 == 0 ? [hours] : [hours, DurationPart(value: minutes % 60, unit: "m")]
        }

        let hours = Int((Double(minutes) / 60).rounded())
        let weeks = hours / 168
        let days = hours % 168 / 24
        var parts: [DurationPart] = []
        if weeks > 0 { parts.append(DurationPart(value: weeks, unit: "w")) }
        parts.append(DurationPart(value: days, unit: "d"))
        // whole weeks and days read fine without a trailing "0h", a bare day count doesn't
        if hours % 24 > 0 || weeks == 0 { parts.append(DurationPart(value: hours % 24, unit: "h")) }
        return parts
    }

    /// A runtime as one string ("5h 12m", "1w 2d 3h", "0h")
    static func duration(_ minutes: Int) -> String {
        durationParts(minutes).map { "\($0.value)\($0.unit)" }.joined(separator: " ")
    }

    /// Top of the chart in hours, the tallest bar snapped up to a step whose half is a whole hour
    static func chartMaxHours(_ buckets: [Bucket]) -> Int {
        let tallest = buckets.map(\.totalMinutes).max() ?? 0
        let steps = [2, 4, 6, 8, 10, 12, 16, 20, 30, 40, 50, 60, 80, 100, 120, 160, 200, 300, 400, 500, 600, 800]
        // past the last step, whole multiples of 200 hours keep the half gridline round
        return steps.first { $0 * 60 >= tallest } ?? (tallest + 12_000 - 1) / 12_000 * 200
    }

    /// Index of the first bucket with the most watched runtime (nil without buckets)
    static func peakIndex(_ buckets: [Bucket]) -> Int? {
        buckets.indices.max { buckets[$0].totalMinutes < buckets[$1].totalMinutes }
    }

    /// Consecutive days with something watched, counted back from today (a today without activity yet doesn't break the run)
    static func currentStreak(_ buckets: [Bucket], now: Date, calendar: Calendar = .current) -> Int {
        guard let today = buckets.firstIndex(where: { calendar.isDate($0.start, inSameDayAs: now) }) else { return 0 }
        var index = buckets[today].totalMinutes > 0 ? today : today - 1
        var days = 0
        while index >= 0, buckets[index].totalMinutes > 0 {
            days += 1
            index -= 1
        }
        return days
    }

    /// The longest run of consecutive buckets with something watched
    static func longestStreak(_ buckets: [Bucket]) -> Int {
        var longest = 0
        var run = 0
        for bucket in buckets {
            run = bucket.totalMinutes > 0 ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    /// Minutes per day from the first bucket's start through today, rounded (nil without buckets)
    static func dailyAverage(_ total: Int, buckets: [Bucket], now: Date, calendar: Calendar = .current) -> Int? {
        guard let first = buckets.first?.start,
              let elapsed = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: now)).day else {
            return nil
        }
        return Int((Double(total) / Double(max(1, elapsed + 1))).rounded())
    }
}
