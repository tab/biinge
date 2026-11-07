import Foundation
import Testing
@testable import Biinge

/// The episodes around the playing one, by number and never by watched progress
struct EpisodeNeighborsTests {
    /// Episodes decoded as the API sends them, each with its number, watched mark and Jellyfin ID (nil for one the server doesn't hold)
    private func episodes(_ rows: [(number: Int, watched: Bool, jellyfinID: String?)]) throws -> [EpisodeSummary] {
        let objects = rows.map { row in
            var object: [String: Any] = ["id": row.number, "title": "E\(row.number)", "number": row.number, "posterPath": "",
                                         "runtime": 50, "overview": "", "watched": row.watched]
            object["jellyfinId"] = row.jellyfinID
            return object
        }
        return try JSONDecoder().decode([EpisodeSummary].self, from: JSONSerialization.data(withJSONObject: objects))
    }

    @Test func aReplayedEpisodeIsFollowedByTheNextNumberNotByProgress() throws {
        // every episode is watched, so progress would point past the season
        let season = try episodes([(1, true, "a"), (2, true, "b"), (3, true, "c")])
        let neighbors = EpisodeNeighbors(season: 1, episode: 2, seasons: [1: season])

        #expect(neighbors.previous?.episode.jellyfinID == "a")
        #expect(neighbors.next?.episode.jellyfinID == "c")
        #expect(neighbors.next?.season == 1)
    }

    @Test func anEpisodeProgressStillReportsUnwatchedIsFollowedByTheOneAfterIt() throws {
        // S1E3 plays while progress still names it the next to watch
        let season = try episodes([(1, true, "a"), (2, true, "b"), (3, false, "c"), (4, false, "d")])
        let neighbors = EpisodeNeighbors(season: 1, episode: 3, seasons: [1: season])

        #expect(neighbors.next?.episode.number == 4)
        #expect(neighbors.next?.episode.jellyfinID == "d")
    }

    @Test func aSeasonsLastEpisodeIsFollowedByTheNextSeasonsFirst() throws {
        let first = try episodes([(1, false, "a"), (2, false, "b")])
        let third = try episodes([(2, false, "y"), (1, false, "x")])
        // specials and a skipped season number never get in the way
        let neighbors = EpisodeNeighbors(season: 1, episode: 2, seasons: [0: try episodes([(1, false, "s")]), 1: first, 3: third])

        #expect(neighbors.next?.season == 3)
        #expect(neighbors.next?.episode.jellyfinID == "x")
    }

    @Test func aSeasonsFirstEpisodeFollowsThePreviousSeasonsLast() throws {
        let first = try episodes([(1, false, "a"), (2, false, "b")])
        let second = try episodes([(1, false, "x"), (2, false, "y")])
        let neighbors = EpisodeNeighbors(season: 2, episode: 1, seasons: [0: try episodes([(1, false, "s")]), 1: first, 2: second])

        #expect(neighbors.previous?.season == 1)
        #expect(neighbors.previous?.episode.jellyfinID == "b")
        #expect(neighbors.next?.episode.jellyfinID == "y")
    }

    @Test func theLastEpisodeOrOneTheServerDoesntHoldHasNoSuccessor() throws {
        let season = try episodes([(1, false, "a"), (2, false, nil)])

        #expect(EpisodeNeighbors(season: 1, episode: 2, seasons: [1: season]).next == nil)
        #expect(EpisodeNeighbors(season: 1, episode: 1, seasons: [1: season]).next == nil)
        #expect(EpisodeNeighbors(season: 1, episode: 1, seasons: [1: season]).previous == nil)
    }

    @Test func specialsAndRegularSeasonsNeverLeadIntoEachOther() throws {
        let specials = try episodes([(1, false, "s1"), (2, false, "s2")])
        let first = try episodes([(1, false, "a"), (2, false, "b")])

        #expect(EpisodeNeighbors(season: 1, episode: 1, seasons: [0: specials, 1: first]).previous == nil)
        #expect(EpisodeNeighbors(season: 0, episode: 2, seasons: [0: specials, 1: first]).next == nil)
        #expect(EpisodeNeighbors(season: 0, episode: 2, seasons: [0: specials, 1: first]).previous?.episode.jellyfinID == "s1")
    }
}

/// The next-episode card's countdown, stepped by hand a second at a time
struct NextEpisodeCountdownTests {
    @Test func startsInTheCreditsAndPlaysAfterTenSeconds() {
        var countdown = NextEpisodeCountdown()
        countdown.update(position: 1000, duration: 2700)
        #expect(countdown.remaining == nil)

        countdown.update(position: 2675, duration: 2700)
        #expect(countdown.remaining == 10)
        let early = (1..<10).map { _ in countdown.tick() }
        #expect(!early.contains(true))
        #expect(countdown.remaining == 1)
        let tenth = countdown.tick()
        #expect(tenth)
        #expect(countdown.remaining == nil)

        // it runs once per episode
        countdown.update(position: 2690, duration: 2700)
        #expect(countdown.remaining == nil)
    }

    @Test func cancelStopsItForTheEpisode() {
        var countdown = NextEpisodeCountdown()
        countdown.update(position: 2675, duration: 2700)
        _ = countdown.tick()

        countdown.cancel()

        #expect(countdown.remaining == nil)
        let fired = countdown.tick()
        #expect(!fired)
        countdown.update(position: 2680, duration: 2700)
        #expect(countdown.remaining == nil)
    }

    @Test func leavingTheCreditsHidesItAndComingBackStartsOver() {
        var countdown = NextEpisodeCountdown()
        countdown.update(position: 2675, duration: 2700)
        _ = countdown.tick()

        countdown.update(position: 600, duration: 2700)
        #expect(countdown.remaining == nil)
        countdown.update(position: 2680, duration: 2700)
        #expect(countdown.remaining == 10)
    }

    @Test func anUnknownRuntimeNeverStartsIt() {
        var countdown = NextEpisodeCountdown()
        countdown.update(position: 5, duration: 0)
        #expect(countdown.remaining == nil)
    }
}
