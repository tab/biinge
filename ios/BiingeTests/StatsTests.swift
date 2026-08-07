import Foundation
import Testing
@testable import Biinge

struct StatsTests {
    private func bucket(_ date: String) -> AccountStats.Bucket {
        AccountStats.Bucket(date: date, movieMinutes: 0, tvMinutes: 0)
    }

    private func components(_ date: Date) -> DateComponents {
        Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
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
        let bucket = AccountStats.Bucket(date: "2026-07-19", movieMinutes: 120, tvMinutes: 42)

        #expect(bucket.totalMinutes == 162)
        #expect(bucket.id == "2026-07-19")
    }

    @Test func periodsBucketByACoarserUnitAsTheyGrow() {
        #expect(StatsPeriod.week.unit == .day)
        #expect(StatsPeriod.month.unit == .day)
        #expect(StatsPeriod.year.unit == .month)
        #expect(StatsPeriod.all.unit == .year)
    }

    @Test func periodsNameTheCurrentCalendarWindow() {
        #expect(StatsPeriod.week.phrase == "this week")
        #expect(StatsPeriod.month.phrase == "this month")
        #expect(StatsPeriod.year.phrase == "this year")
        #expect(StatsPeriod.all.phrase == "all time")
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
            { "date": "2026-07-19", "movieMinutes": 120, "tvMinutes": 42 },
            { "date": "2026-07-20", "movieMinutes": 0, "tvMinutes": 90 }
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
}
