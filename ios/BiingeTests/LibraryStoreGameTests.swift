import Foundation
import Testing
@testable import Biinge

extension LibraryStoreTests {
    @Test func aGameLoadDuringAPendingWriteKeepsTheNewerState() async throws {
        let games = GameStore(apiClient: apiClient)
        await games.load()
        LibraryListProtocol.patchDelay = 0.8
        // the PATCH answer decodes, so the move lands and only the load it held back reloads the lists (no failed write's resync)
        #expect(throws: Never.self) { try JSONDecoder().decode(GameDetails.self, from: Data(LibraryListProtocol.patchedDetails.utf8)) }

        await games.toggle(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, target: .played)
        // the server still lists the game in Playing until the PATCH lands
        await games.load()

        #expect(games.currentState(id: 30) == .played)
        try await waitForReloadAfterPatch { games.isLoading }
        #expect(games.playedGames.map(\.id) == [30])
        #expect(games.playingGames.isEmpty)
        #expect(games.loadError == nil)
    }

    @Test func aGameWriteThatEndsDuringTheFetchLoadsAgain() async throws {
        let games = GameStore(apiClient: apiClient)
        await games.load()
        LibraryListProtocol.getDelay = 0.5

        let loading = Task { await games.load() }
        try await waitForHeldGets(3)
        await games.toggle(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, target: .played)
        await loading.value

        // the fetch from before the PATCH still had the game in Playing, so the load fetched again
        #expect(games.playedGames.map(\.id) == [30])
        #expect(games.playingGames.isEmpty)
    }

    @Test func aGameKeepsItsPinInWantAndPlayingAndLosesItInPlayed() async throws {
        let games = GameStore(apiClient: apiClient)
        await games.load()
        await games.setPinned(id: 30, pinned: true)

        await games.move(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, target: .want)
        #expect(games.currentState(id: 30) == .want)
        #expect(games.isPinned(id: 30))

        await games.move(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, target: .played)
        #expect(games.currentState(id: 30) == .played)
        #expect(!games.isPinned(id: 30))
        // the writes run after move returns, so wait for them rather than leak them into the next test
        for _ in 0..<100 where LibraryListProtocol.answered.filter({ $0.hasPrefix("PATCH") }).count < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aMoveToTheCurrentListChangesNothing() async throws {
        let movies = MovieStore(apiClient: apiClient, undoWindow: .seconds(30))
        let series = SeriesStore(apiClient: apiClient, undoWindow: .seconds(30))
        let games = GameStore(apiClient: apiClient, undoWindow: .seconds(30))
        await movies.load()
        await series.load()
        await games.load()

        await movies.move(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .want).value
        await series.move(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        await games.move(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, target: .playing)
        // a write would run after move returns, so the test waits for the show's and gives a game's time to go out
        _ = await series.addFailure(id: 20)
        for _ in 0..<20 where LibraryListProtocol.answered.allSatisfy({ $0.hasPrefix("GET") }) {
            try await Task.sleep(for: .milliseconds(10))
        }

        // unlike a toggle, picking the list a title sits in neither removes it nor writes
        #expect(movies.currentState(id: 10) == .want && !movies.isRemovalPending(id: 10))
        #expect(series.currentState(id: 20) == .watching && !series.isRemovalPending(id: 20))
        #expect(games.currentState(id: 30) == .playing && !games.isRemovalPending(id: 30))
        #expect(LibraryListProtocol.answered.allSatisfy { $0.hasPrefix("GET") })
    }

    @Test func anEpisodeUnmarkDuringAMoveToWatchedWinsOverTheMovesProgress() async throws {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()
        LibraryListProtocol.patchDelay = 0.5
        let season = SeasonSummary(id: 101, title: "Season 1", number: 1, posterPath: "", episodesCount: 2, airDate: nil)
        let episode = try JSONDecoder().decode(
            EpisodeSummary.self, from: Data(#"{"id": 201, "title": "Freedom Day", "number": 1, "posterPath": "", "runtime": 50, "overview": ""}"#.utf8)
        )
        let details = SeriesDetails(
            id: 20, title: "Silo", posterPath: "", pinned: false, state: .watching,
            overview: "", status: "Returning Series", releaseDate: nil,
            seasonsCount: 1, episodesCount: 10, rating: nil, genres: [],
            credits: [], recommendations: [], videos: [], seasons: [season], jellyfinID: nil
        )

        // the move's writes are held, and it counts as a mark, so reads and marks from before it give way
        await series.move(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        #expect(series.episodeMarks[20] == 1)
        // another screen unmarks episode 201 while the move still marks every episode
        let unmark = Task { try await series.setEpisodeWatched(false, episode: episode, season: season, seasonEpisodes: [episode], details: details) }
        for _ in 0..<100 where series.progress(id: 20) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await series.addFailure(id: 20) == nil)

        // the move's answer has landed with 201 and the unmark's DELETE is still held, yet the newer unmark keeps 201 out
        #expect(LibraryListProtocol.answered.contains("POST /api/v1/series/20/watched"))
        #expect(!LibraryListProtocol.answered.contains { $0.hasPrefix("DELETE") })
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
        try await unmark.value
    }

    @Test func aFailedGameLoadReportsTheErrorAndKeepsTheLists() async {
        LibraryListProtocol.fails = true
        let games = GameStore(apiClient: apiClient)
        await games.load()

        #expect(games.loadError != nil)
        #expect(!games.hasLoaded)

        LibraryListProtocol.fails = false
        await games.load()
        #expect(games.loadError == nil)
        #expect(games.playingGames.map(\.id) == [30])

        LibraryListProtocol.fails = true
        await games.load()

        #expect(games.loadError != nil)
        #expect(games.hasLoaded)
        #expect(games.playingGames.map(\.id) == [30])
    }

    @Test func aRemovalOfATitleInNoListDoesNothing() async {
        let movies = MovieStore(apiClient: apiClient, undoWindow: .seconds(30))
        let series = SeriesStore(apiClient: apiClient, undoWindow: .seconds(30))
        await movies.load()
        await series.load()

        await movies.remove(id: 11).value
        series.remove(id: 21)

        #expect(!movies.isRemovalPending(id: 11) && !series.isRemovalPending(id: 21))
        #expect(movies.wantMovies.map(\.id) == [10])
        #expect(series.watchingSeries.map(\.id) == [20])
    }

    @Test func aMovieMovedToWatchedLosesItsPin() async {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()
        await movies.setPinned(id: 10, pinned: true)

        await movies.move(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched).value

        // only Want pins a movie
        #expect(movies.currentState(id: 10) == .watched)
        #expect(!movies.isPinned(id: 10))
    }

    @Test func aSeriesMovedToWantKeepsItsPinAndItsEpisodes() async {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()
        await series.setPinned(id: 20, pinned: true)

        await series.move(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .want)

        #expect(await series.addFailure(id: 20) == nil)
        #expect(series.currentState(id: 20) == .want)
        #expect(series.isPinned(id: 20))
        #expect(!LibraryListProtocol.answered.contains("POST /api/v1/series/20/watched"))
    }

    @Test func aSeriesMovedToWatchedMarksEveryAiredEpisodeAndStaysWatchedUnpinned() async throws {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()
        await series.setPinned(id: 20, pinned: true)

        await series.move(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)

        #expect(await series.addFailure(id: 20) == nil)
        #expect(series.currentState(id: 20) == .watched)
        #expect(!series.isPinned(id: 20))
        #expect(series.progress(id: 20)?.state == .watched)
        #expect(series.progress(id: 20)?.watchedEpisodes == [201])
        #expect(series.watchedSeries.map(\.watchedEpisodesCount) == [1])
        // episode 202 hasn't aired, so the mark leaves it out
        let body = try #require(LibraryListProtocol.seriesMarkBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let seasons = try #require(body["seasons"] as? [[String: Any]])
        #expect(seasons.map { $0["id"] as? Int } == [101])
        #expect(seasons.flatMap { ($0["episodes"] as? [[String: Any]] ?? []).map { $0["id"] as? Int } } == [201])
        let answered = LibraryListProtocol.answered
        // the specials never load, and the API's Watching for a show in production gives way to the user's Watched
        #expect(answered.contains("GET /api/v1/series/20/season/1"))
        #expect(!answered.contains("GET /api/v1/series/20/season/0"))
        #expect(Array(answered.suffix(2)) == ["POST /api/v1/series/20/watched", "PATCH /api/v1/series/20"])
    }

    @Test func aSeriesAddedToWatchedIsCreatedThenHasEveryAiredEpisodeMarked() async {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()

        await series.move(id: 21, title: "Dark", posterPath: "", seasonsCount: 1, episodesCount: 2, status: "Ended", target: .watched)

        #expect(await series.addFailure(id: 21) == nil)
        #expect(series.watchedSeries.map(\.id) == [21])
        #expect(series.progress(id: 21)?.watchedEpisodes == [201])
        #expect(LibraryListProtocol.answered.filter { !$0.hasPrefix("GET") }
            == ["POST /api/v1/series", "POST /api/v1/series/21/watched", "PATCH /api/v1/series/21"])
    }
}

extension LibraryListProtocol {
    /// The body of the last whole-show mark's POST
    nonisolated(unsafe) static var seriesMarkBody: Data?

    /// Keeps the whole-show mark's body, which URLSession hands the protocol as a stream
    func recordSeriesMark() {
        guard let stream = request.httpBodyStream else { return }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 { data.append(buffer, count: count) }
        Self.seriesMarkBody = data
    }
}
