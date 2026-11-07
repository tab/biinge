import Foundation
import Testing
@testable import Biinge

/// The series details' next episode: the first aired unwatched one, else episode 1 of season 1
struct NextEpisodePickTests {
    /// Noon UTC, so the local calendar day is the 15th in every time zone the tests run in
    private let today = Date(timeIntervalSince1970: 1_781_524_800)
    private let aired = "2026-01-10"
    private let unaired = "2026-12-01"

    /// Season summaries as the API sends them, with season id = 10 × number
    private func seasons(_ numbers: [Int]) throws -> [SeasonSummary] {
        let objects = numbers.map { ["id": $0 * 10, "title": "Season \($0)", "number": $0, "posterPath": "", "episodesCount": 3] as [String: Any] }
        return try JSONDecoder().decode([SeasonSummary].self, from: JSONSerialization.data(withJSONObject: objects))
    }

    /// A season's episodes as the API sends them, with episode id = 100 × season + number and an air date each (nil for none)
    private func episodes(season: Int, _ airDates: [String?]) throws -> [EpisodeSummary] {
        let objects = airDates.enumerated().map { index, airDate in
            var object: [String: Any] = ["id": season * 100 + index + 1, "title": "E\(index + 1)", "number": index + 1, "posterPath": "",
                                         "runtime": 50, "overview": "", "jellyfinId": "s\(season)e\(index + 1)"]
            object["airDate"] = airDate
            return object
        }
        return try JSONDecoder().decode([EpisodeSummary].self, from: JSONSerialization.data(withJSONObject: objects))
    }

    private func progress(seasons: [Int] = [], episodes: [Int]) -> WatchProgress {
        WatchProgress(id: 1, state: .watching, trackedState: .watching, watchedSeasons: seasons, watchedEpisodes: episodes)
    }

    @Test func midSeasonPicksTheFirstUnwatchedEpisode() throws {
        let pick = NextEpisodePick(
            seasons: try seasons([1]), episodes: [1: try episodes(season: 1, [aired, aired, aired])],
            progress: progress(episodes: [101]), today: today
        )

        #expect(pick.season == 1)
        #expect(pick.episode?.number == 2)
    }

    @Test func aWatchedSeasonHandsOverToTheNextSeasonsFirstEpisode() throws {
        let pick = NextEpisodePick(
            seasons: try seasons([1, 2]),
            episodes: [1: try episodes(season: 1, [aired, aired]), 2: try episodes(season: 2, [aired, aired])],
            progress: progress(seasons: [10], episodes: [101, 102]), today: today
        )

        #expect(pick.season == 2)
        #expect(pick.episode?.number == 1)
    }

    @Test func theNextSeasonLoadsBeforeThePickSettles() throws {
        let pick = NextEpisodePick(
            seasons: try seasons([1, 2]), episodes: [1: try episodes(season: 1, [aired])],
            progress: progress(seasons: [10], episodes: [101]), today: today
        )

        #expect(pick.season == 2)
        #expect(pick.episode == nil)
    }

    @Test func aFullyWatchedSeriesOffersTheFirstEpisodeAgain() throws {
        let pick = NextEpisodePick(
            seasons: try seasons([1, 2]),
            episodes: [1: try episodes(season: 1, [aired, aired]), 2: try episodes(season: 2, [aired])],
            progress: progress(seasons: [10, 20], episodes: [101, 102, 201]), today: today
        )

        #expect(pick.season == 1)
        #expect(pick.episode?.number == 1)
    }

    @Test func aCaughtUpAiringSeriesOffersTheFirstEpisodeNotAnUnairedOne() throws {
        // season 2 is airing: E1 and E2 are watched, E3 and E4 haven't aired, and season 3 is announced
        let pick = NextEpisodePick(
            seasons: try seasons([1, 2, 3]),
            episodes: [
                1: try episodes(season: 1, [aired, aired]),
                2: try episodes(season: 2, [aired, aired, unaired, nil]),
                3: try episodes(season: 3, [unaired]),
            ],
            progress: progress(seasons: [10], episodes: [101, 102, 201, 202]), today: today
        )

        #expect(pick.season == 1)
        #expect(pick.episode?.number == 1)
    }

    @Test func aCaughtUpSeriesDoesNotWaitOnAnAnnouncedSeason() throws {
        // season 3 is announced but not loaded, and the caught-up season 2 already settles the pick
        let pick = NextEpisodePick(
            seasons: try seasons([1, 2, 3]),
            episodes: [1: try episodes(season: 1, [aired]), 2: try episodes(season: 2, [aired, unaired])],
            progress: progress(seasons: [10], episodes: [101, 201]), today: today
        )

        #expect(pick.season == 1)
        #expect(pick.episode?.number == 1)
    }

    @Test func aSeasonMarkedWatchedIsSkippedWithoutItsEpisodes() throws {
        // season 1 carries the season mark only, and its episodes never load
        let pick = NextEpisodePick(
            seasons: try seasons([1, 2]), episodes: [2: try episodes(season: 2, [aired, aired])],
            progress: progress(seasons: [10], episodes: []), today: today
        )

        #expect(pick.season == 2)
        #expect(pick.episode?.number == 1)
    }

    @Test func anUnairedEpisodeIsNeverPicked() throws {
        let pick = NextEpisodePick(
            seasons: try seasons([1]), episodes: [1: try episodes(season: 1, [unaired, nil])],
            progress: progress(episodes: []), today: today
        )

        #expect(pick.episode == nil)
        #expect(pick.season == nil)
    }

    @Test func specialsAreIgnored() throws {
        // the unwatched specials come first by number but never count
        let pick = NextEpisodePick(
            seasons: try seasons([0, 1]),
            episodes: [0: try episodes(season: 0, [aired, aired]), 1: try episodes(season: 1, [aired, aired])],
            progress: progress(episodes: [101]), today: today
        )

        #expect(pick.season == 1)
        #expect(pick.episode?.number == 2)
    }

    @Test func aSeriesWithOnlySpecialsOffersNothing() throws {
        let pick = NextEpisodePick(
            seasons: try seasons([0]), episodes: [0: try episodes(season: 0, [aired])], progress: progress(episodes: []), today: today
        )

        #expect(pick.episode == nil)
        #expect(pick.season == nil)
    }

    @Test func withoutProgressTheEpisodesOwnWatchedMarkCounts() throws {
        let objects: [[String: Any]] = [
            ["id": 101, "title": "E1", "number": 1, "posterPath": "", "runtime": 50, "overview": "", "airDate": aired, "watched": true],
            ["id": 102, "title": "E2", "number": 2, "posterPath": "", "runtime": 50, "overview": "", "airDate": aired],
        ]
        let list = try JSONDecoder().decode([EpisodeSummary].self, from: JSONSerialization.data(withJSONObject: objects))
        let pick = NextEpisodePick(seasons: try seasons([1]), episodes: [1: list], progress: nil, today: today)

        #expect(pick.episode?.number == 2)
    }

    @Test func aFailedReplaySeasonBlocksThePickOnlyWhileAnotherSeasonShows() throws {
        // season 2 is shown and complete, season 1 is marked watched and uncached, so the replay waits on season 1
        let pick = NextEpisodePick(
            seasons: try seasons([1, 2]), episodes: [2: try episodes(season: 2, [aired])],
            progress: progress(seasons: [10, 20], episodes: [201]), today: today
        )
        let settled = NextEpisodePick(
            seasons: try seasons([1]), episodes: [1: try episodes(season: 1, [aired])], progress: progress(episodes: []), today: today
        )

        #expect(pick.season == 1)
        #expect(pick.failedSeason(failures: [1: "offline"], shown: 2) == 1)
        #expect(pick.failedSeason(failures: [1: "offline"], shown: 1) == nil)
        #expect(pick.failedSeason(failures: [:], shown: 2) == nil)
        #expect(pick.failedSeason(failures: [2: "offline"], shown: 1) == nil)
        #expect(settled.failedSeason(failures: [1: "offline"], shown: 2) == nil)
    }
}
