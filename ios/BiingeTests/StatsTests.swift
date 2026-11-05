import Foundation
import Testing
@testable import Biinge

struct StatsTests {
    private func bucket(_ date: String) -> AccountStats.Bucket {
        AccountStats.Bucket(date: date, movieMinutes: 0, seriesMinutes: 0)
    }

    private func components(_ date: Date) -> DateComponents {
        Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    }

    // the bucket keys parse in the gregorian calendar's default time zone, so the tests only pin the locale
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ key: String) -> Date {
        bucket(key).start
    }

    /// Dense day buckets from `first`, one per entry in `minutes`, all of it TV
    private func days(from first: String, _ minutes: [Int]) -> [AccountStats.Bucket] {
        minutes.enumerated().map { offset, value in
            let day = calendar.date(byAdding: .day, value: offset, to: date(first)) ?? .distantPast
            let parts = components(day)
            let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            return AccountStats.Bucket(date: key, movieMinutes: 0, seriesMinutes: value)
        }
    }

    private func stats(movies: Int, episodes: Int, watched: Int = 0, activity: [AccountStats.Bucket]?) -> AccountStats {
        AccountStats(
            movies: .init(want: 0, watched: 0, minutes: movies),
            series: .init(want: 0, watching: nil, watched: 0),
            episodes: .init(watched: watched, minutes: episodes),
            activity: activity,
            games: nil
        )
    }

    @Test func bucketStartParsesADayKey() {
        let parts = components(bucket("2026-07-19").start)

        #expect(parts.year == 2026)
        #expect(parts.month == 7)
        #expect(parts.day == 19)
    }

    @Test func bucketStartFallsBackWhenTheKeyIsMalformed() {
        #expect(bucket("2026-07").start == .distantPast)
        #expect(bucket("").start == .distantPast)
        #expect(bucket("not-a-date").start == .distantPast)
    }

    @Test func bucketTotalSumsBothKinds() {
        let bucket = AccountStats.Bucket(date: "2026-07-19", movieMinutes: 120, seriesMinutes: 42)

        #expect(bucket.totalMinutes == 162)
        #expect(bucket.id == "2026-07-19")
    }

    @Test func periodsNameTheCurrentCalendarWindow() {
        let now = date("2026-11-03")

        #expect(StatsPeriod.week.range(now: now, calendar: calendar) == "This week")
        #expect(StatsPeriod.month.range(now: now, calendar: calendar) == "This month")
        #expect(StatsPeriod.year.range(now: now, calendar: calendar) == "2026")
        #expect(StatsPeriod.all.range(now: now, calendar: calendar) == "All time")
    }

    @Test func bucketStartParsesAYearKey() {
        let parts = components(bucket("2024-01-01").start)

        #expect(parts.year == 2024)
        #expect(parts.month == 1)
        #expect(parts.day == 1)
    }

    @Test func periodsSendTheirNameAsTheQueryValue() {
        #expect(StatsPeriod.allCases.map(\.rawValue) == ["week", "month", "year", "all"])
    }

    @Test func decodesAStatsPayload() throws {
        let json = """
        {
          "period": "week",
          "movies": { "want": 2, "watched": 3, "minutes": 340 },
          "series": { "want": 1, "watched": 9 },
          "episodes": { "watched": 11, "minutes": 460 },
          "games": { "want": 4, "played": 2, "minutes": 3600 },
          "activity": [
            { "date": "2026-07-19", "movieMinutes": 120, "seriesMinutes": 42 },
            { "date": "2026-07-20", "movieMinutes": 0, "seriesMinutes": 90 }
          ]
        }
        """

        let stats = try JSONDecoder().decode(AccountStats.self, from: Data(json.utf8))

        #expect(stats.movies.watched == 3)
        #expect(stats.episodes.minutes == 460)
        #expect(stats.activity?.count == 2)
        #expect(stats.activity?.first?.movieMinutes == 120)
        #expect(stats.games?.want == 4)
        #expect(stats.games?.played == 2)
        #expect(stats.games?.minutes == 3600)
        // a bounded period carries no playing count, the same way series carries no watching
        #expect(stats.games?.playing == nil)
        #expect(components(stats.activity?.first?.start ?? .distantPast).day == 19)
    }

    @Test func aBoundedPeriodCarriesNoWatchingCount() throws {
        let json = """
        {
          "period": "week",
          "movies": { "want": 1, "watched": 3, "minutes": 340 },
          "series": { "want": 0, "watched": 9 },
          "episodes": { "watched": 11, "minutes": 460 }
        }
        """

        let stats = try JSONDecoder().decode(AccountStats.self, from: Data(json.utf8))

        #expect(stats.series.watching == nil)
        #expect(stats.movies.want == 1)
        #expect(stats.series.want == 0)
        #expect(stats.series.watched == 9)
    }

    // an API deployed before games reached statistics omits the key entirely
    @Test func decodesAPayloadWithoutGames() throws {
        let json = """
        {
          "period": "all",
          "movies": { "want": 1, "watched": 2, "minutes": 3 },
          "series": { "want": 4, "watching": 5, "watched": 6 },
          "episodes": { "watched": 7, "minutes": 8 }
        }
        """

        let stats = try JSONDecoder().decode(AccountStats.self, from: Data(json.utf8))

        #expect(stats.games == nil)
        #expect(stats.movies.watched == 2)
    }

    @Test func theWantBarCountsAdditionsOnABoundedPeriod() {
        #expect(StatsPeriod.week.wantLabel == "Added")
        #expect(StatsPeriod.month.wantLabel == "Added")
        #expect(StatsPeriod.year.wantLabel == "Added")
        #expect(StatsPeriod.all.wantLabel == "Want")
    }

    @Test func decodesAPayloadWithoutActivity() throws {
        let json = """
        {
          "period": "all",
          "movies": { "want": 1, "watched": 2, "minutes": 3 },
          "series": { "want": 4, "watching": 5, "watched": 6 },
          "episodes": { "watched": 7, "minutes": 8 }
        }
        """

        let stats = try JSONDecoder().decode(AccountStats.self, from: Data(json.utf8))

        #expect(stats.activity == nil)
        #expect(stats.series.watching == 5)
    }

    @Test(arguments: [
        (0, "0h"),
        (42, "42m"),
        (60, "1h"),
        (312, "5h 12m"),
        (1439, "23h 59m"),
        (1440, "1d 0h"),
        (2 * 1440 + 3 * 60 + 29, "2d 3h"),
        (2 * 1440 + 3 * 60 + 30, "2d 4h"),
        (7 * 1440, "1w 0d"),
        (13 * 1440 + 7 * 60, "1w 6d 7h"),
        (25 * 1440, "3w 4d"),
    ])
    func durationsReadInTheLargestUnits(minutes: Int, expected: String) {
        #expect(AccountStats.duration(minutes) == expected)
    }

    @Test func durationPartsKeepEachUnitApartForTheHero() {
        #expect(AccountStats.durationParts(312) == [DurationPart(value: 5, unit: "h"), DurationPart(value: 12, unit: "m")])
        #expect(AccountStats.durationParts(0) == [DurationPart(value: 0, unit: "h")])
    }

    @Test func theSplitSharesAlwaysAddUpToAHundred() {
        let split = stats(movies: 156, episodes: 704, activity: nil)

        #expect(split.totalMinutes == 860)
        #expect(split.moviePercent == 18)
        #expect(split.seriesPercent == 82)
    }

    @Test func theMovieShareRoundsToTheNearestPercent() {
        let split = stats(movies: 2, episodes: 1, activity: nil)

        #expect(split.moviePercent == 67)
        #expect(split.seriesPercent == 33)
    }

    @Test func nothingWatchedSplitsIntoNoShares() {
        let empty = stats(movies: 0, episodes: 0, activity: nil)

        #expect(empty.moviePercent == 0)
        #expect(empty.seriesPercent == 0)
    }

    @Test(arguments: [
        (0, 2),
        (90, 2),
        (120, 2),
        (121, 4),
        (5 * 60 + 30, 6),
        (13 * 60, 16),
        (35 * 60, 40),
        (460 * 60, 500),
        (801 * 60, 1000),
    ])
    func theChartTopSnapsToAStepWithAWholeHalf(tallest: Int, expected: Int) {
        let buckets = [AccountStats.Bucket(date: "2026-11-02", movieMinutes: tallest / 2, seriesMinutes: tallest - tallest / 2)]

        #expect(AccountStats.chartMaxHours(buckets) == expected)
    }

    @Test func thePeakIsTheFirstBusiestBucket() {
        #expect(AccountStats.peakIndex(days(from: "2026-11-02", [30, 90, 90, 10])) == 1)
        #expect(AccountStats.peakIndex(days(from: "2026-11-02", [0, 0, 0])) == 0)
        #expect(AccountStats.peakIndex([]) == nil)
    }

    @Test func calloutsNameDaysMonthsAndYears() {
        let now = date("2026-11-03")

        #expect(StatsPeriod.week.calloutLabel(for: date("2026-11-03"), now: now, calendar: calendar) == "Today")
        #expect(StatsPeriod.week.calloutLabel(for: date("2026-10-31"), now: now, calendar: calendar) == "Saturday, Oct 31")
        #expect(StatsPeriod.month.calloutLabel(for: date("2026-11-01"), now: now, calendar: calendar) == "Sunday, Nov 1")
        #expect(StatsPeriod.year.calloutLabel(for: date("2026-07-01"), now: now, calendar: calendar) == "July")
        #expect(StatsPeriod.year.calloutLabel(for: date("2026-11-01"), now: now, calendar: calendar) == "November so far")
        #expect(StatsPeriod.all.calloutLabel(for: date("2020-01-01"), now: now, calendar: calendar) == "2020")
        #expect(StatsPeriod.all.calloutLabel(for: date("2026-01-01"), now: now, calendar: calendar) == "2026 so far")
    }

    @Test func weekAxisUsesNarrowWeekdays() {
        let week = days(from: "2026-11-02", Array(repeating: 0, count: 7))

        #expect(week.indices.map { StatsPeriod.week.axisLabel(at: $0, of: week, calendar: calendar) } == ["M", "T", "W", "T", "F", "S", "S"])
    }

    @Test func monthAxisLabelsEveryWeekStartingWithTheMonth() {
        let month = days(from: "2026-11-01", Array(repeating: 0, count: 30))
        let labels = month.indices.map { StatsPeriod.month.axisLabel(at: $0, of: month, calendar: calendar) }

        #expect(labels.filter { !$0.isEmpty } == ["Nov 1", "8", "15", "22", "29"])
        #expect(labels[1].isEmpty)
    }

    @Test func yearAxisUsesNarrowMonths() {
        let year = (1...12).map { bucket(String(format: "2026-%02d-01", $0)) }
        let labels = year.indices.map { StatsPeriod.year.axisLabel(at: $0, of: year, calendar: calendar) }

        #expect(labels == ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"])
    }

    @Test func allTimeAxisShortensYearsAndThinsALongHistory() {
        let eight = (2019...2026).map { bucket("\($0)-01-01") }
        let twenty = (2007...2026).map { bucket("\($0)-01-01") }

        #expect(eight.indices.map { StatsPeriod.all.axisLabel(at: $0, of: eight, calendar: calendar) }
            == ["’19", "’20", "’21", "’22", "’23", "’24", "’25", "’26"])
        // twenty years label every third, which keeps the row at seven labels
        #expect(twenty.indices.map { StatsPeriod.all.axisLabel(at: $0, of: twenty, calendar: calendar) }.filter { !$0.isEmpty }.count == 7)
    }

    @Test func theCurrentStreakCountsBackFromToday() {
        let week = days(from: "2026-11-02", [0, 30, 40, 50, 0, 0, 0])

        #expect(AccountStats.currentStreak(week, now: date("2026-11-05"), calendar: calendar) == 3)
        // today without activity yet keeps yesterday's run alive
        #expect(AccountStats.currentStreak(week, now: date("2026-11-06"), calendar: calendar) == 3)
        #expect(AccountStats.currentStreak(week, now: date("2026-11-07"), calendar: calendar) == 0)
        // a cached week that no longer holds today has no current run
        #expect(AccountStats.currentStreak(week, now: date("2026-11-12"), calendar: calendar) == 0)
    }

    @Test func theLongestStreakIsTheLongestRun() {
        #expect(AccountStats.longestStreak(days(from: "2026-11-01", [10, 10, 0, 5, 5, 5, 0, 1])) == 3)
        #expect(AccountStats.longestStreak(days(from: "2026-11-01", [0, 0])) == 0)
    }

    @Test func theDailyAverageDividesByTheDaysElapsed() {
        let week = days(from: "2026-11-02", Array(repeating: 0, count: 7))

        // Monday through Wednesday is three days
        #expect(AccountStats.dailyAverage(489, buckets: week, now: date("2026-11-04"), calendar: calendar) == 163)
        #expect(AccountStats.dailyAverage(489, buckets: [], now: date("2026-11-04"), calendar: calendar) == nil)
    }

    @Test func aWeekShowsTheCurrentStreakAndTheBusiestWeekday() {
        // Monday and Tuesday make the longer run, while the current one is Thursday alone
        let week = days(from: "2026-11-02", [120, 120, 0, 60, 0, 0, 0])
        let tiles = StatsPeriod.week.highlights(
            for: stats(movies: 0, episodes: 300, watched: 1842, activity: week), now: date("2026-11-05"), calendar: calendar
        )

        #expect(tiles == [
            StatsHighlight(symbol: "flame", value: "1 day", label: "Current streak"),
            StatsHighlight(symbol: "calendar", value: "Monday", label: "Busiest day"),
            StatsHighlight(symbol: "tv", value: "1,842", label: "Episodes"),
            StatsHighlight(symbol: "clock", value: "1h 15m", label: "Daily average"),
        ])
    }

    @Test func aMonthShowsTheLongestStreak() {
        let month = days(from: "2026-11-01", [20, 0, 20, 20] + Array(repeating: 0, count: 26))
        let tiles = StatsPeriod.month.highlights(for: stats(movies: 0, episodes: 60, activity: month), now: date("2026-11-10"), calendar: calendar)

        #expect(tiles.first == StatsHighlight(symbol: "flame", value: "2 days", label: "Longest streak"))
        // under an hour a day reads in minutes
        #expect(tiles.last == StatsHighlight(symbol: "clock", value: "6 min", label: "Daily average"))
    }

    @Test func aYearAndAllTimeCarryNoStreak() {
        let year = (1...12).map { AccountStats.Bucket(date: String(format: "2026-%02d-01", $0), movieMinutes: 0, seriesMinutes: $0 == 7 ? 600 : 60) }
        let history = [bucket("2025-01-01"), AccountStats.Bucket(date: "2026-01-01", movieMinutes: 60, seriesMinutes: 0)]

        let yearTiles = StatsPeriod.year.highlights(for: stats(movies: 0, episodes: 1260, activity: year), now: date("2026-11-03"), calendar: calendar)
        let allTiles = StatsPeriod.all.highlights(for: stats(movies: 60, episodes: 0, activity: history), now: date("2026-11-03"), calendar: calendar)

        #expect(yearTiles.map(\.label) == ["Busiest month", "Episodes", "Daily average"])
        #expect(yearTiles.first?.value == "July")
        #expect(allTiles.map(\.label) == ["Busiest year", "Episodes", "Daily average"])
        #expect(allTiles.first?.value == "2026")
    }

    @Test func nothingWatchedHasNoBusiestBucket() {
        let week = days(from: "2026-11-02", Array(repeating: 0, count: 7))
        let tiles = StatsPeriod.week.highlights(for: stats(movies: 0, episodes: 0, activity: week), now: date("2026-11-04"), calendar: calendar)

        #expect(tiles[1] == StatsHighlight(symbol: "calendar", value: "None", label: "Busiest day"))
        #expect(tiles[0].value == "0 days")
    }

    // the API keys its buckets by gregorian year, so a Japanese calendar's era years ("8" for 2026) never reach the screen
    @Test func yearsStayGregorianInAnyCalendar() {
        var japanese = Calendar(identifier: .japanese)
        japanese.locale = Locale(identifier: "en_US")
        let now = date("2026-11-03")
        let history = [bucket("2025-01-01"), AccountStats.Bucket(date: "2026-01-01", movieMinutes: 60, seriesMinutes: 0)]
        let tiles = StatsPeriod.all.highlights(for: stats(movies: 60, episodes: 0, activity: history), now: now, calendar: japanese)

        #expect(StatsPeriod.year.range(now: now, calendar: japanese) == "2026")
        #expect(StatsPeriod.all.calloutLabel(for: date("2025-01-01"), now: now, calendar: japanese) == "2025")
        #expect(StatsPeriod.all.axisLabel(at: 1, of: history, calendar: japanese) == "’26")
        #expect(tiles.first?.value == "2026")
    }
}
