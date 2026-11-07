import Foundation
import Testing
@testable import Biinge

/// Answers the biinge list endpoints with one movie, one show and one game after getDelay, or with a server error while the running test sets fails (or for paths under failsPath), and moves the movie and the show to Watched and the game to Played on a PATCH (a create's POST leaves them) that answers after patchDelay (an episode, season or whole-show mark's POST or DELETE answers after patchDelay with the show's progress, and a show's and its season 1's details answer at once; a sign-in answers with the account's tokens, and holdsDelete holds a title's DELETE)
final class LibraryListProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var fails = false
    /// A path prefix answered with a server error while every other path succeeds
    nonisolated(unsafe) static var failsPath: String?
    /// Seconds a PATCH waits before it answers
    nonisolated(unsafe) static var patchDelay: TimeInterval = 0
    /// Whether a PATCH has moved the movie and the show to Watched
    nonisolated(unsafe) static var watched = false
    /// The Jellyfin item the show's list entry names (none by default)
    nonisolated(unsafe) static var seriesJellyfinID: String?
    /// Seconds a GET waits before it answers (with the lists as they stood when it arrived)
    nonisolated(unsafe) static var getDelay: TimeInterval = 0
    /// Every request answered, as "METHOD path", in order (behind a lock, as the answers append off the test's thread)
    static var answered: [String] {
        get { lock.withLock { recorded } }
        set { lock.withLock { recorded = newValue } }
    }
    /// How many GETs wait out getDelay now
    static var heldCount: Int { lock.withLock { heldGets.count } }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [String] = []
    nonisolated(unsafe) private static var heldGets: [UUID: LibraryListProtocol] = [:]
    /// The PATCH waiting out patchDelay
    nonisolated(unsafe) static var pendingPatch: LibraryListProtocol?
    /// The account whose tokens and user a sign-in, a refresh or a user read answers with
    nonisolated(unsafe) static var account = "a"
    /// Whether the next DELETE of a library title waits for releaseDelete
    nonisolated(unsafe) static var holdsDelete = false
    /// The Authorization header of every DELETE of a library title that arrived, in order
    static var deleteAuthorizations: [String] {
        get { lock.withLock { authorizations } }
        set { lock.withLock { authorizations = newValue } }
    }
    /// Whether a DELETE waits for releaseDelete now
    static var isDeleteHeld: Bool { lock.withLock { heldDelete != nil } }
    nonisolated(unsafe) private static var authorizations: [String] = []
    nonisolated(unsafe) private static var heldDelete: LibraryListProtocol?

    /// Answers the held DELETE with `status`
    static func releaseDelete(status: Int) {
        let held = lock.withLock { () -> LibraryListProtocol? in
            defer { heldDelete = nil }
            return heldDelete
        }
        guard let held, let url = held.request.url else { return }
        held.answer(url: url, method: "DELETE", body: "{}", status: status)
    }

    /// A PATCH answer that MovieDetails, SeriesDetails and GameDetails all decode
    static let patchedDetails = #"{"id": 0, "title": "", "posterPath": "", "pinned": false, "state": "watched", "overview": "", "genres": [], "platforms": [], "#
        + #""credits": [], "recommendations": [], "videos": [], "seasons": []}"#

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return }
        // an episode mark answers with its show's progress, holding its episode after a POST and dropping it after a DELETE
        let isEpisodeMark = url.path.hasSuffix("/watched")
        let markPath = isEpisodeMark ? url.pathComponents : []
        // a whole-show mark's path stops at the show, whose season 101 holds aired episode 201 (still Watching, as for a show in production; the body is kept)
        let isSeriesMark = markPath.count == 6
        // a season mark's path stops at the season, whose one episode the stub numbers as the season's ID plus 100
        let isSeasonMark = markPath.count == 8
        let marked = isSeriesMark ? "201" : isSeasonMark ? Int(markPath[6]).map { "\($0 + 100)" } ?? "" : isEpisodeMark ? markPath[8] : ""
        let seasons = isSeriesMark ? "101" : isSeasonMark && method == "POST" ? markPath[6] : ""
        let progress = isEpisodeMark
            ? #"{"id": \#(markPath[4]), "state": "watching", "trackedState": "watching", "watchedSeasons": [\#(seasons)], "watchedEpisodes": [\#(method == "POST" ? marked : "")]}"#
            : ""
        if url.path == "/api/v1/users/sessions" || url.path == "/api/v1/users/tokens" {
            answer(url: url, method: method, body: #"{"access_token": "\#(Self.account)-access", "refresh_token": "\#(Self.account)-refresh"}"#)
            return
        }
        if url.path == "/api/v1/accounts/me" {
            let user = #"{"id": "00000000-0000-0000-0000-000000000001", "login": "\#(Self.account)", "email": "\#(Self.account)@example.com", "appearance": "system"}"#
            answer(url: url, method: method, body: user)
            return
        }
        if method == "DELETE", !isEpisodeMark {
            Self.deleteAuthorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            if Self.holdsDelete {
                Self.holdsDelete = false
                Self.lock.withLock { Self.heldDelete = self }
                return
            }
        }
        if isSeriesMark, method == "POST" { recordSeriesMark() }
        if method == "PATCH" || method == "POST" || (method == "DELETE" && isEpisodeMark) {
            // the delayed answer reaches the protocol through shared state, as a capture of it can't cross threads
            Self.pendingPatch = self
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.patchDelay) {
                // a failed write leaves the lists as they were
                if method == "PATCH", !Self.fails, Self.failsPath.map({ url.path.hasPrefix($0) }) != true { Self.watched = true }
                Self.pendingPatch?.answer(url: url, method: method, body: isEpisodeMark ? progress : Self.patchedDetails)
            }
            return
        }
        // a show's details list its specials and season 1, whose details hold aired episode 201 and unaired 202
        if method == "GET", url.pathComponents.count == 5, url.path.hasPrefix("/api/v1/series/") {
            let seasons = #"[{"id": 100, "title": "Specials", "number": 0, "posterPath": "", "episodesCount": 1}, {"id": 101, "title": "Season 1", "number": 1, "posterPath": "", "episodesCount": 2}]"#
            answer(url: url, method: method, body: #"{"id": \#(url.lastPathComponent), "title": "Silo", "posterPath": "", "pinned": false, "state": "watching", "overview": "", "#
                + #""status": "Returning Series", "genres": [], "credits": [], "recommendations": [], "videos": [], "seasons": \#(seasons)}"#)
            return
        }
        if method == "GET", url.path.hasSuffix("/season/1") {
            let episodes = [201, 202].map { #"{"id": \#($0), "title": "", "number": \#($0 - 200), "posterPath": "", "runtime": 50, "overview": "", "airDate": "\#($0 == 201 ? 2020 : 2999)-01-01"}"# }
            answer(url: url, method: method, body: #"{"id": 101, "title": "Season 1", "number": 1, "posterPath": "", "overview": "", "episodes": [\#(episodes.joined(separator: ", "))]}"#)
            return
        }
        let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "type" }?.value
        let movie = #"{"id": 10, "title": "Heat", "posterPath": "", "pinned": false, "state": "want", "jellyfinId": "j10"}"#
        let seriesJellyfinID = Self.seriesJellyfinID.map { #", "jellyfinId": "\#($0)""# } ?? ""
        let seriesItem = #"{"id": 20, "title": "Silo", "posterPath": "", "pinned": false, "state": "watching", "episodesCount": 10, "watchedEpisodesCount": 4\#(seriesJellyfinID)}"#
        let game = #"{"id": 30, "title": "Astro Bot", "posterPath": "co8ae6", "pinned": false, "state": "\#(Self.watched ? "played" : "playing")"}"#
        let item: String? = switch (url.path, type) {
        case ("/api/v1/movies", "want"): Self.watched ? nil : movie
        case ("/api/v1/movies", "watched"): Self.watched ? movie : nil
        case ("/api/v1/series", "watching"): Self.watched ? nil : seriesItem
        case ("/api/v1/series", "watched"): Self.watched ? seriesItem : nil
        case ("/api/v1/games", "playing"), ("/api/v1/games", "played"): Self.watched == (type == "played") ? game : nil
        default: nil
        }
        let body = #"{"data": [\#(item ?? "")], "meta": {"page": 1, "per": 10000, "total": \#(item == nil ? 0 : 1)}}"#
        guard Self.getDelay > 0 else {
            answer(url: url, method: method, body: body)
            return
        }
        // the closure carries a token, as a capture of the protocol can't cross threads
        let token = UUID()
        Self.lock.withLock { Self.heldGets[token] = self }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.getDelay) {
            let held = Self.lock.withLock { Self.heldGets.removeValue(forKey: token) }
            held?.answer(url: url, method: method, body: body)
        }
    }

    private func answer(url: URL, method: String, body: String, status: Int = 200) {
        let fails = Self.fails || Self.failsPath.map { url.path.hasPrefix($0) } == true
        let status = fails ? 500 : status
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        Self.lock.withLock { Self.recorded.append("\(method) \(url.path)") }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((fails ? #"{"error": "internal error"}"# : body).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct LibraryStoreTests {
    let apiClient: Biinge.APIClient

    init() {
        LibraryListProtocol.fails = false
        LibraryListProtocol.failsPath = nil
        LibraryListProtocol.patchDelay = 0
        LibraryListProtocol.getDelay = 0
        LibraryListProtocol.seriesJellyfinID = nil
        LibraryListProtocol.watched = false
        LibraryListProtocol.answered = []
        LibraryListProtocol.account = "a"
        LibraryListProtocol.holdsDelete = false
        LibraryListProtocol.deleteAuthorizations = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryListProtocol.self]
        apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
    }

    @Test func aFailedFirstLoadReportsTheErrorInsteadOfAnEmptyList() async {
        LibraryListProtocol.fails = true
        let movies = MovieStore(apiClient: apiClient)
        let series = SeriesStore(apiClient: apiClient)

        await movies.load()
        await series.load()

        #expect(movies.loadError != nil)
        #expect(series.loadError != nil)
        #expect(!movies.hasLoaded)
        #expect(!series.hasLoaded)
    }

    @Test func aFailedRefreshKeepsTheListsAndASuccessClearsTheError() async {
        let movies = MovieStore(apiClient: apiClient)
        let series = SeriesStore(apiClient: apiClient)
        await movies.load()
        await series.load()
        #expect(movies.wantMovies.map(\.jellyfinID) == ["j10"])
        #expect(series.watchingSeries.map(\.jellyfinID) == [nil])

        LibraryListProtocol.fails = true
        await movies.load()
        await series.load()

        #expect(movies.loadError != nil)
        #expect(series.loadError != nil)
        #expect(movies.hasLoaded && series.hasLoaded)
        #expect(movies.wantMovies.map(\.id) == [10])
        #expect(series.watchingSeries.map(\.id) == [20])

        LibraryListProtocol.fails = false
        await movies.load()
        await series.load()

        #expect(movies.loadError == nil)
        #expect(series.loadError == nil)
    }

    /// Waits until the queue's reload after the PATCH has answered and finished (a few seconds at most)
    func waitForReloadAfterPatch(isLoading: () -> Bool) async throws {
        for _ in 0..<100 {
            let answered = LibraryListProtocol.answered
            if let patch = answered.lastIndex(where: { $0.hasPrefix("PATCH") }), answered.count > patch + 1, !isLoading() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("the queue never reloaded after the PATCH")
    }

    /// Waits until the stub has answered the given number of PATCHes (it answers one at a time)
    private func waitForPatches(_ count: Int) async throws {
        for _ in 0..<100 where LibraryListProtocol.answered.filter({ $0.hasPrefix("PATCH") }).count < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(LibraryListProtocol.answered.filter { $0.hasPrefix("PATCH") }.count == count)
    }

    @Test func aPinAMetadataRefreshAndAProgressUpdateKeepTheJellyfinItem() async throws {
        LibraryListProtocol.seriesJellyfinID = "j20"
        let movies = MovieStore(apiClient: apiClient)
        let series = SeriesStore(apiClient: apiClient)
        await movies.load()
        await series.load()

        await movies.setPinned(id: 10, pinned: true)
        try await waitForPatches(1)
        await series.setPinned(id: 20, pinned: true)
        try await waitForPatches(2)
        movies.refreshMetadata(id: 10, title: "Heat (1995)", posterPath: "/heat.jpg")
        series.refreshMetadata(id: 20, title: "Silo (2023)", posterPath: "/silo.jpg")
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: nil, watchedSeasons: [], watchedEpisodes: [1, 2, 3, 4, 5]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: true)

        // only a load brings the Jellyfin item, so every local rewrite of the entry carries it over
        #expect(movies.wantMovies.map(\.jellyfinID) == ["j10"])
        #expect(movies.wantMovies.map(\.title) == ["Heat (1995)"])
        #expect(series.watchingSeries.map(\.jellyfinID) == ["j20"])
        #expect(series.watchingSeries.map(\.watchedEpisodesCount) == [5])
    }

    @Test func aSeriesAddedHereWaitsForALoadForItsJellyfinItem() async throws {
        LibraryListProtocol.seriesJellyfinID = "j20"
        let series = SeriesStore(apiClient: apiClient)
        await series.load()

        await series.toggle(id: 30, title: "Severance", posterPath: "", seasonsCount: 2, episodesCount: 19, status: "", target: .want)

        // only the API matches a Jellyfin item, so the new entry has none until the next load
        #expect(series.wantSeries.map(\.id) == [30])
        #expect(series.wantSeries.map(\.jellyfinID) == [nil])
        #expect(series.watchingSeries.map(\.jellyfinID) == ["j20"])
        for _ in 0..<100 where !LibraryListProtocol.answered.contains("POST /api/v1/series") {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Waits until the given number of GETs wait out getDelay, so a write goes out during their fetch
    func waitForHeldGets(_ count: Int) async throws {
        for _ in 0..<100 where LibraryListProtocol.heldCount < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(LibraryListProtocol.heldCount == count)
    }

    @Test func aMovieWriteThatEndsDuringTheFetchLoadsAgain() async throws {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()
        LibraryListProtocol.getDelay = 0.5

        let loading = Task { await movies.load() }
        try await waitForHeldGets(2)
        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        await loading.value

        // the fetch from before the PATCH still had the movie in Want, so the load fetched again
        #expect(movies.watchedMovies.map(\.id) == [10])
        #expect(movies.wantMovies.isEmpty)
    }

    @Test func aMovieWriteStillPendingAfterTheFetchLoadsOnceItEnds() async throws {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()
        LibraryListProtocol.getDelay = 0.3
        LibraryListProtocol.patchDelay = 0.8

        let loading = Task { await movies.load() }
        try await waitForHeldGets(2)
        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        await loading.value

        // the stale fetch never replaced the local mark, and the queue loads after the PATCH
        #expect(movies.currentState(id: 10) == .watched)
        try await waitForReloadAfterPatch { movies.isLoading }
        #expect(movies.watchedMovies.map(\.id) == [10])
        #expect(movies.wantMovies.isEmpty)
    }

    @Test func aFailedMovieWriteEndsAfterTheResyncRestoresTheState() async throws {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()
        LibraryListProtocol.failsPath = "/api/v1/movies/10"

        let write = await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        #expect(movies.currentState(id: 10) == .watched)
        await write.value

        // the details screens set Home's hidden movies from this state, so it already holds the API's answer
        #expect(movies.currentState(id: 10) == .want)
        #expect(LibraryListProtocol.answered.last?.hasPrefix("GET /api/v1/movies") == true)
    }

    @Test func aFailedMovieWriteEndsAfterTheResyncBehindALaterWrite() async throws {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()
        LibraryListProtocol.failsPath = "/api/v1/movies/10"
        LibraryListProtocol.patchDelay = 0.3

        let write = await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .want)
        await write.value

        // the PATCH failed while the POST was still queued, so the task waited for the resync after the POST
        #expect(movies.currentState(id: 10) == .want)
        #expect(LibraryListProtocol.answered.contains("POST /api/v1/movies"))
        #expect(LibraryListProtocol.answered.last?.hasPrefix("GET /api/v1/movies") == true)
    }

    @Test func aSeriesWriteThatEndsDuringTheFetchLoadsAgain() async throws {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()
        LibraryListProtocol.getDelay = 0.5

        let loading = Task { await series.load() }
        try await waitForHeldGets(3)
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        await loading.value

        // the fetch from before the PATCH still had the show in Watching, so the load fetched again
        #expect(series.watchedSeries.map(\.id) == [20])
        #expect(series.watchingSeries.isEmpty)
        #expect(await series.addFailure(id: 20) == nil)
    }

    @Test func aSeriesWriteStillPendingAfterTheFetchLoadsOnceItEnds() async throws {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()
        LibraryListProtocol.getDelay = 0.3
        LibraryListProtocol.patchDelay = 0.8

        let loading = Task { await series.load() }
        try await waitForHeldGets(3)
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        await loading.value

        // the stale fetch never replaced the local mark, and the queue loads after the PATCH
        #expect(series.currentState(id: 20) == .watched)
        try await waitForReloadAfterPatch { series.isLoading }
        #expect(series.watchedSeries.map(\.id) == [20])
        #expect(series.watchingSeries.isEmpty)
        // the move's write ends after the queue's load, which comes after its last PATCH
        #expect(await series.addFailure(id: 20) == nil)
        #expect(LibraryListProtocol.answered.last == "GET /api/v1/series")
    }

    @Test func aMovieLoadDuringAPendingWriteKeepsTheNewerMark() async throws {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()
        LibraryListProtocol.patchDelay = 0.8

        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        await movies.load()

        #expect(movies.currentState(id: 10) == .watched)
        try await waitForReloadAfterPatch { movies.isLoading }
        #expect(movies.watchedMovies.map(\.id) == [10])
        #expect(movies.wantMovies.isEmpty)
    }

    @Test func aSeriesLoadDuringAPendingWriteKeepsTheNewerMark() async throws {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()
        LibraryListProtocol.patchDelay = 0.8

        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        await series.load()

        #expect(series.currentState(id: 20) == .watched)
        try await waitForReloadAfterPatch { series.isLoading }
        #expect(series.watchedSeries.map(\.id) == [20])
        #expect(series.watchingSeries.isEmpty)
        #expect(await series.addFailure(id: 20) == nil)
        #expect(LibraryListProtocol.answered.last == "GET /api/v1/series")
    }

    @Test func aLaterEpisodeUnmarkWinsOverAnEarlierMarkStillInFlight() async throws {
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

        // one screen marks the episode and its POST is held, then another unmarks it
        let mark = Task { try await series.setEpisodeWatched(true, episode: episode, season: season, seasonEpisodes: [episode], details: details) }
        for _ in 0..<100 where series.progress(id: 20)?.watchedEpisodes != [201] {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(series.progress(id: 20)?.watchedEpisodes == [201])
        let unmark = Task { try await series.setEpisodeWatched(false, episode: episode, season: season, seasonEpisodes: [episode], details: details) }
        for _ in 0..<100 where series.progress(id: 20)?.watchedEpisodes != [] {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
        try await mark.value
        // the mark's answer has landed and the unmark's DELETE is still held
        #expect(!LibraryListProtocol.answered.contains { $0.hasPrefix("DELETE") })
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
        try await unmark.value

        // the unmark went out after the mark, and the mark's late answer never restored the episode
        let path = "/api/v1/series/20/seasons/101/episodes/201/watched"
        #expect(LibraryListProtocol.answered.filter { $0.hasSuffix(path) } == ["POST \(path)", "DELETE \(path)"])
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
    }

    @Test func aLaterEpisodeUnmarkWinsOverAnEarlierSeasonMarkStillInFlight() async throws {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()
        LibraryListProtocol.patchDelay = 0.5
        let season = SeasonSummary(id: 101, title: "Season 1", number: 1, posterPath: "", episodesCount: 1, airDate: nil)
        let episode = try JSONDecoder().decode(
            EpisodeSummary.self, from: Data(#"{"id": 201, "title": "Freedom Day", "number": 1, "posterPath": "", "runtime": 50, "overview": ""}"#.utf8)
        )
        let details = SeriesDetails(
            id: 20, title: "Silo", posterPath: "", pinned: false, state: .watching,
            overview: "", status: "Returning Series", releaseDate: nil,
            seasonsCount: 1, episodesCount: 10, rating: nil, genres: [],
            credits: [], recommendations: [], videos: [], seasons: [season], jellyfinID: nil
        )

        // the series screen marks the season and its POST is held, then an episode sheet unmarks its episode
        let mark = Task { try await series.setSeasonWatched(true, season: season, seasonEpisodes: [episode], details: details) }
        for _ in 0..<100 where series.progress(id: 20)?.watchedEpisodes != [201] {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(series.progress(id: 20)?.watchedSeasons == [101])
        let unmark = Task { try await series.setEpisodeWatched(false, episode: episode, season: season, seasonEpisodes: [episode], details: details) }
        for _ in 0..<100 where series.progress(id: 20)?.watchedEpisodes != [] {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await mark.value
        // the season's answer has landed and the unmark's DELETE is still held
        #expect(!LibraryListProtocol.answered.contains { $0.hasPrefix("DELETE") })
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
        try await unmark.value

        // the unmark went out after the season mark, and the season's late answer never restored the episode
        #expect(LibraryListProtocol.answered.filter { $0.hasSuffix("/watched") } == [
            "POST /api/v1/series/20/seasons/101/watched", "DELETE /api/v1/series/20/seasons/101/episodes/201/watched",
        ])
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
    }

    @Test func aFailedMarkRollsBackWhileAMarkOnAnotherSeriesWaitsBehindIt() async throws {
        let series = SeriesStore(apiClient: apiClient)
        await series.load()
        LibraryListProtocol.patchDelay = 0.5
        // show 20's mark and its progress refresh fail, so only the snapshot can roll it back
        LibraryListProtocol.failsPath = "/api/v1/series/20/"
        let decoder = JSONDecoder()
        let seasonA = SeasonSummary(id: 101, title: "Season 1", number: 1, posterPath: "", episodesCount: 2, airDate: nil)
        let episodeA = try decoder.decode(
            EpisodeSummary.self, from: Data(#"{"id": 201, "title": "Freedom Day", "number": 1, "posterPath": "", "runtime": 50, "overview": ""}"#.utf8)
        )
        let detailsA = SeriesDetails(
            id: 20, title: "Silo", posterPath: "", pinned: false, state: .watching,
            overview: "", status: "Returning Series", releaseDate: nil,
            seasonsCount: 1, episodesCount: 10, rating: nil, genres: [],
            credits: [], recommendations: [], videos: [], seasons: [seasonA], jellyfinID: nil
        )
        let seasonB = SeasonSummary(id: 102, title: "Season 1", number: 1, posterPath: "", episodesCount: 2, airDate: nil)
        let episodeB = try decoder.decode(
            EpisodeSummary.self, from: Data(#"{"id": 301, "title": "Pilot", "number": 1, "posterPath": "", "runtime": 50, "overview": ""}"#.utf8)
        )
        let detailsB = SeriesDetails(
            id: 30, title: "Severance", posterPath: "", pinned: false, state: .watching,
            overview: "", status: "Returning Series", releaseDate: nil,
            seasonsCount: 1, episodesCount: 10, rating: nil, genres: [],
            credits: [], recommendations: [], videos: [], seasons: [seasonB], jellyfinID: nil
        )
        series.apply(
            WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: []),
            id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: false
        )

        // show 20's mark is held, then show 30 is marked behind it in the queue
        let markA = Task { try await series.setEpisodeWatched(true, episode: episodeA, season: seasonA, seasonEpisodes: [episodeA], details: detailsA) }
        for _ in 0..<100 where series.progress(id: 20)?.watchedEpisodes != [201] {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(series.progress(id: 20)?.watchedEpisodes == [201])
        let markB = Task { try await series.setEpisodeWatched(true, episode: episodeB, season: seasonB, seasonEpisodes: [episodeB], details: detailsB) }
        for _ in 0..<100 where series.progress(id: 30)?.watchedEpisodes != [301] {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(series.progress(id: 30)?.watchedEpisodes == [301])

        await #expect(throws: (any Error).self) { try await markA.value }
        try await markB.value

        // show 30's later mark left show 20's rollback alone, and show 30 keeps its own answer
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
        #expect(series.progress(id: 30)?.watchedEpisodes == [301])
    }
}

/// Removals with Undo, which share the suite's serialized stub
extension LibraryStoreTests {
    @Test func anUndoneSeriesRemovalComesBackWithItsEpisodesAndPinAndSendsNoDelete() async throws {
        let series = SeriesStore(apiClient: apiClient, undoWindow: .milliseconds(200))
        await series.load()
        await series.setPinned(id: 20, pinned: true)
        try await waitForPatches(1)
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2, 3, 4]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: true)

        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        #expect(series.currentState(id: 20) == nil)
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
        series.undoRemoval(id: 20)
        // well past the window, which Undo ended without a write
        try await Task.sleep(for: .milliseconds(500))

        #expect(series.watchingSeries.map(\.id) == [20])
        #expect(series.isPinned(id: 20))
        #expect(series.watchingSeries.map(\.watchedEpisodesCount) == [4])
        #expect(series.progress(id: 20)?.watchedEpisodes == [1, 2, 3, 4])
        #expect(!LibraryListProtocol.answered.contains { $0.hasPrefix("DELETE") })
    }

    @Test func aSeriesRemovalSendsItsDeleteOnlyWhenTheUndoWindowEnds() async throws {
        let series = SeriesStore(apiClient: apiClient, undoWindow: .milliseconds(400))
        await series.load()

        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!LibraryListProtocol.answered.contains { $0.hasPrefix("DELETE") })
        let failure = await series.removalFailure(id: 20)

        #expect(failure == nil)
        #expect(LibraryListProtocol.answered.contains("DELETE /api/v1/series/20"))
        #expect(series.currentState(id: 20) == nil)
    }

    @Test func aFailedRemovalCommitBringsTheSeriesBackAndReportsTheError() async throws {
        let series = SeriesStore(apiClient: apiClient, undoWindow: .milliseconds(100))
        await series.load()
        LibraryListProtocol.failsPath = "/api/v1/series/20"
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: false)

        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        let failure = await series.removalFailure(id: 20)

        // the failure ends the wait once the resync has listed the show again
        #expect(failure != nil)
        #expect(LibraryListProtocol.answered.contains("DELETE /api/v1/series/20"))
        #expect(series.watchingSeries.map(\.id) == [20])
        #expect(series.progress(id: 20)?.watchedEpisodes == [1, 2])
    }

    @Test func aLoadKeepsAPendingRemovalHiddenAndALaterRemovalCommitsIt() async throws {
        let movies = MovieStore(apiClient: apiClient, undoWindow: .seconds(30))
        await movies.load()

        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .want)
        // the server still lists the movie, which the load leaves hidden
        await movies.load()
        #expect(movies.wantMovies.isEmpty)
        await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .want)
        await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .want)
        for _ in 0..<100 where !LibraryListProtocol.answered.contains("DELETE /api/v1/movies/10") {
            try await Task.sleep(for: .milliseconds(10))
        }

        // the second removal ended the first one's window, and its own still runs
        #expect(LibraryListProtocol.answered.contains("DELETE /api/v1/movies/10"))
        #expect(!LibraryListProtocol.answered.contains("DELETE /api/v1/movies/11"))
        movies.undoRemoval(id: 11)
        #expect(movies.wantMovies.map(\.id) == [11])
    }

    @Test func reAddingARemovedMovieSendsTheRemovalFirst() async throws {
        let movies = MovieStore(apiClient: apiClient, undoWindow: .seconds(30))
        await movies.load()

        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .want)
        #expect(movies.isRemovalPending(id: 10))
        let write = await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .want)
        await write.value

        // the second tap ended the window, so the Undo toast closes and the server sees the DELETE before the POST
        #expect(!movies.isRemovalPending(id: 10))
        let answered = LibraryListProtocol.answered
        let delete = try #require(answered.firstIndex(of: "DELETE /api/v1/movies/10"))
        let create = try #require(answered.firstIndex(of: "POST /api/v1/movies"))
        #expect(delete < create)
        #expect(movies.wantMovies.map(\.id) == [10])
    }

    @Test func anEpisodeMarkOnARemovedSeriesSendsTheRemovalFirst() async throws {
        let series = SeriesStore(apiClient: apiClient, undoWindow: .seconds(30))
        await series.load()
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

        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        try await series.setEpisodeWatched(true, episode: episode, season: season, seasonEpisodes: [episode], details: details)

        // the mark ended the window, so the Undo toast closes and the server deletes the show before the mark tracks it again
        #expect(!series.isRemovalPending(id: 20))
        let answered = LibraryListProtocol.answered
        let delete = try #require(answered.firstIndex(of: "DELETE /api/v1/series/20"))
        let mark = try #require(answered.firstIndex(of: "POST /api/v1/series/20/seasons/101/episodes/201/watched"))
        #expect(delete < mark)
        #expect(series.progress(id: 20)?.watchedEpisodes == [201])
    }

    @Test func aProgressReadDuringARemovalWindowLeavesTheSeriesHidden() async throws {
        let series = SeriesStore(apiClient: apiClient, undoWindow: .seconds(30))
        await series.load()
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: false)

        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        // a details screen's read from before the removal lands
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2, 3]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: false)

        #expect(series.watchingSeries.isEmpty)
        #expect(series.progress(id: 20)?.watchedEpisodes == [])
        series.undoRemoval(id: 20)
        #expect(series.watchingSeries.map(\.id) == [20])
        #expect(series.progress(id: 20)?.watchedEpisodes == [1, 2])
        #expect(!LibraryListProtocol.answered.contains { $0.hasPrefix("DELETE") })
    }

    @Test func aLogoutDuringTheUndoWindowSendsNoDelete() async throws {
        // logging out clears the simulator's stored biinge tokens, which the other suites share
        let keychain = Keychain()
        let stored = [KeychainKey.accessToken, .refreshToken].map { ($0, keychain.read($0)) }
        defer {
            for (key, value) in stored {
                if let value { keychain.save(value, for: key) } else { keychain.delete(key) }
            }
        }
        let authManager = AuthManager()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryListProtocol.self]
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: authManager, configuration: configuration)
        let movies = MovieStore(apiClient: apiClient, undoWindow: .milliseconds(100))
        let series = SeriesStore(apiClient: apiClient, undoWindow: .milliseconds(100))
        let games = GameStore(apiClient: apiClient, undoWindow: .milliseconds(100))
        await movies.load()
        await series.load()
        await games.load()

        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .want)
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        await games.toggle(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, target: .playing)
        // the next account to sign in would lend the retained stores its token
        authManager.logout()
        // the three windows run together, so each is still pending when its wait begins
        async let movieFailure = movies.removalFailure(id: 10)
        async let seriesFailure = series.removalFailure(id: 20)
        async let gameFailure = games.removalFailure(id: 30)
        LibraryListProtocol.account = "b"
        try await authManager.login(using: apiClient, email: "b@example.com", password: "secret")
        let failures = await [movieFailure, seriesFailure, gameFailure]

        #expect(failures.allSatisfy { $0 == nil })
        #expect(!movies.isRemovalPending(id: 10) && !series.isRemovalPending(id: 20) && !games.isRemovalPending(id: 30))

        #expect(LibraryListProtocol.deleteAuthorizations.isEmpty)
    }

    @Test func aRemovalRejectedAfterAnotherAccountSignsInIsNotRetriedAsThatAccount() async throws {
        // signing in and out replaces the simulator's stored biinge tokens, which the other suites share
        let keychain = Keychain()
        let stored = [KeychainKey.accessToken, .refreshToken].map { ($0, keychain.read($0)) }
        defer {
            for (key, value) in stored {
                if let value { keychain.save(value, for: key) } else { keychain.delete(key) }
            }
        }
        let authManager = AuthManager()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryListProtocol.self]
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: authManager, configuration: configuration)
        try await authManager.login(using: apiClient, email: "a@example.com", password: "secret")
        let movies = MovieStore(apiClient: apiClient, undoWindow: .milliseconds(100))
        await movies.load()

        // account A's DELETE is held past its window while B signs in, then answers that A's token expired
        LibraryListProtocol.holdsDelete = true
        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .want)
        async let failure = movies.removalFailure(id: 10)
        for _ in 0..<100 where !LibraryListProtocol.isDeleteHeld {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(LibraryListProtocol.isDeleteHeld)
        let session = authManager.sessionsEnded
        authManager.logout()
        LibraryListProtocol.account = "b"
        try await authManager.login(using: apiClient, email: "b@example.com", password: "secret")
        LibraryListProtocol.releaseDelete(status: 401)

        #expect(await failure != nil)
        #expect(LibraryListProtocol.deleteAuthorizations == ["Bearer a-access"])
        #expect(!LibraryListProtocol.answered.contains("POST /api/v1/users/tokens"))
        #expect(authManager.accessToken == "b-access")

        // a DELETE bound to the ended session is not sent at all
        await #expect(throws: APIError.self) { try await apiClient.deleteMovie(id: 10, session: session) }
        #expect(LibraryListProtocol.deleteAuthorizations.count == 1)
    }

    @Test func aFailedRemovalCommitBringsTheTitleBackWhenTheResyncFailsToo() async throws {
        let movies = MovieStore(apiClient: apiClient, undoWindow: .milliseconds(100))
        let series = SeriesStore(apiClient: apiClient, undoWindow: .milliseconds(100))
        let games = GameStore(apiClient: apiClient, undoWindow: .milliseconds(100))
        await movies.load()
        await series.load()
        await games.load()
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: false)

        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .want)
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        await games.toggle(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, target: .playing)
        // offline, so the DELETEs and the list reads after them all fail
        LibraryListProtocol.fails = true
        // the three windows run together, so each is still pending when its wait begins
        async let movieFailure = movies.removalFailure(id: 10)
        async let seriesFailure = series.removalFailure(id: 20)
        async let gameFailure = games.removalFailure(id: 30)
        let failures = await [movieFailure, seriesFailure, gameFailure]

        #expect(failures.allSatisfy { $0 != nil })
        #expect(LibraryListProtocol.answered.filter { $0.hasPrefix("DELETE") }.count == 3)

        #expect(movies.loadError != nil && series.loadError != nil && games.loadError != nil)
        #expect(movies.wantMovies.map(\.id) == [10])
        #expect(series.watchingSeries.map(\.id) == [20])
        #expect(series.progress(id: 20)?.watchedEpisodes == [1, 2])
        #expect(games.playingGames.map(\.id) == [30])
    }

    @Test func aFailedAddOrMoveRevertsAndReportsTheErrorWhenTheResyncFailsToo() async throws {
        let movies = MovieStore(apiClient: apiClient)
        let series = SeriesStore(apiClient: apiClient)
        await movies.load()
        await series.load()
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: false)
        // offline, so the writes and the list reads after them all fail
        LibraryListProtocol.fails = true

        await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .want)
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        #expect(movies.currentState(id: 11) == .want)
        #expect(series.currentState(id: 20) == .watched)
        async let movieFailure = movies.addFailure(id: 11)
        async let seriesFailure = series.addFailure(id: 20)
        let failures = await [movieFailure, seriesFailure]

        // the buttons read the store, so they turn back as the failures arrive
        #expect(failures.allSatisfy { $0 != nil })
        #expect(movies.loadError != nil && series.loadError != nil)
        #expect(movies.currentState(id: 11) == nil)
        #expect(movies.wantMovies.map(\.id) == [10])
        #expect(series.watchingSeries.map(\.id) == [20])
        #expect(series.watchedSeries.isEmpty)
        #expect(series.progress(id: 20)?.state == .watching)
        #expect(series.progress(id: 20)?.watchedEpisodes == [1, 2])
    }

    @Test func wantThenWatchedBothFailingLeaveAnUntrackedTitleUntrackedWhenTheResyncFailsToo() async throws {
        let movies = MovieStore(apiClient: apiClient)
        let series = SeriesStore(apiClient: apiClient)
        await movies.load()
        await series.load()
        // offline, and each write is held, so Watched queues behind Want before either fails
        LibraryListProtocol.fails = true
        LibraryListProtocol.patchDelay = 0.2

        // the stub holds one write at a time, so the stores take turns
        await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .want)
        await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .watched)
        #expect(await movies.addFailure(id: 11) != nil)
        await series.toggle(id: 21, title: "Dark", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .want)
        await series.toggle(id: 21, title: "Dark", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        #expect(await series.addFailure(id: 21) != nil)

        #expect(movies.loadError != nil && series.loadError != nil)
        #expect(movies.currentState(id: 11) == nil)
        #expect(movies.wantMovies.map(\.id) == [10])
        #expect(series.currentState(id: 21) == nil)
        #expect(series.watchingSeries.map(\.id) == [20])
    }

    @Test func anUndoAfterAFailedMoveWhileListsFailRestoresTheTitleAsTheServerHasIt() async throws {
        let movies = MovieStore(apiClient: apiClient, undoWindow: .seconds(30))
        let series = SeriesStore(apiClient: apiClient, undoWindow: .seconds(30))
        await movies.load()
        await series.load()
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: false)
        // offline, and each move is held, so the title is removed from Watched before its move fails
        LibraryListProtocol.fails = true
        LibraryListProtocol.patchDelay = 0.2

        let write = await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        #expect(movies.isRemovalPending(id: 10))
        await write.value
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        #expect(series.isRemovalPending(id: 20))
        #expect(await series.addFailure(id: 20) != nil)
        #expect(movies.loadError != nil && series.loadError != nil)
        movies.undoRemoval(id: 10)
        series.undoRemoval(id: 20)

        #expect(movies.wantMovies.map(\.id) == [10] && movies.watchedMovies.isEmpty)
        #expect(series.watchingSeries.map(\.id) == [20] && series.watchedSeries.isEmpty)
        #expect(series.progress(id: 20)?.state == .watching)
        #expect(series.progress(id: 20)?.watchedEpisodes == [1, 2])
    }

    @Test func aRemovalOfAnAddThatFailsEndsWithNothingToUndo() async throws {
        let movies = MovieStore(apiClient: apiClient, undoWindow: .seconds(30))
        await movies.load()
        LibraryListProtocol.fails = true
        LibraryListProtocol.patchDelay = 0.2

        let write = await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .want)
        await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .want)
        #expect(movies.isRemovalPending(id: 11))
        await write.value

        // the server never listed it, so the removal ends and Undo has nothing to bring back
        #expect(!movies.isRemovalPending(id: 11))
        movies.undoRemoval(id: 11)
        #expect(movies.currentState(id: 11) == nil)
    }

    @Test func aLandedAddReportsNoFailure() async throws {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()

        await movies.toggle(id: 11, title: "Ronin", posterPath: "", runtime: 0, target: .want)

        #expect(await movies.addFailure(id: 11) == nil)
        #expect(LibraryListProtocol.answered.contains("POST /api/v1/movies"))
    }

    @Test func anUndoAfterAnEarlierMarkFailedLeavesTheMarkOut() async throws {
        let series = SeriesStore(apiClient: apiClient, undoWindow: .seconds(30))
        await series.load()
        LibraryListProtocol.patchDelay = 0.5
        // the mark and its progress refresh fail, so the mark rolls back to the progress before it
        LibraryListProtocol.failsPath = "/api/v1/series/20/"
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
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 10, pinned: false)

        // the mark's POST is held, and the show is removed behind it
        let mark = Task { try await series.setEpisodeWatched(true, episode: episode, season: season, seasonEpisodes: [episode], details: details) }
        for _ in 0..<100 where series.progress(id: 20)?.watchedEpisodes.contains(201) != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(series.progress(id: 20)?.watchedEpisodes.contains(201) == true)
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watching)
        await #expect(throws: (any Error).self) { try await mark.value }
        #expect(series.watchingSeries.isEmpty)
        series.undoRemoval(id: 20)

        #expect(series.watchingSeries.map(\.id) == [20])
        #expect(series.progress(id: 20)?.watchedEpisodes == [1, 2])
        #expect(!LibraryListProtocol.answered.contains { $0.hasPrefix("DELETE /api/v1/series") })
    }

    @Test(arguments: [false, true])
    func anUndoAfterAFailedLastMarkWhileListsFailRestoresTheSeriesAsBeforeTheMark(seasonMark: Bool) async throws {
        let series = SeriesStore(apiClient: apiClient, undoWindow: .seconds(30))
        await series.load()
        LibraryListProtocol.patchDelay = 0.5
        // the mark, its progress refresh and the list reads after it all fail, so nothing from the server repairs the removal's entry
        LibraryListProtocol.failsPath = "/api/v1/series"
        let season = SeasonSummary(id: 101, title: "Season 1", number: 1, posterPath: "", episodesCount: 1, airDate: nil)
        let episode = try JSONDecoder().decode(
            EpisodeSummary.self, from: Data(#"{"id": 201, "title": "Freedom Day", "number": 1, "posterPath": "", "runtime": 50, "overview": ""}"#.utf8)
        )
        let details = SeriesDetails(
            id: 20, title: "Silo", posterPath: "", pinned: false, state: .watching,
            overview: "", status: "Ended", releaseDate: nil,
            seasonsCount: 1, episodesCount: 3, rating: nil, genres: [],
            credits: [], recommendations: [], videos: [], seasons: [season], jellyfinID: nil
        )
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [1, 2]),
                    id: 20, title: "Silo", posterPath: "", episodesCount: 3, pinned: false)

        // the last mark moves the show to Watched while its write is held, and the show is removed from Watched behind it
        let mark = Task {
            if seasonMark {
                try await series.setSeasonWatched(true, season: season, seasonEpisodes: [episode], details: details)
            } else {
                try await series.setEpisodeWatched(true, episode: episode, season: season, seasonEpisodes: [episode], details: details)
            }
        }
        for _ in 0..<100 where series.watchedSeries.first?.id != 20 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(series.watchedSeries.map(\.watchedEpisodesCount) == [3])
        await series.toggle(id: 20, title: "Silo", posterPath: "", seasonsCount: 0, episodesCount: 0, status: "", target: .watched)
        await #expect(throws: (any Error).self) { try await mark.value }
        #expect(series.loadError != nil)
        series.undoRemoval(id: 20)

        #expect(series.watchedSeries.isEmpty)
        #expect(series.watchingSeries.map(\.id) == [20])
        #expect(series.watchingSeries.map(\.watchedEpisodesCount) == [2])
        #expect(series.progress(id: 20)?.state == .watching)
        #expect(series.progress(id: 20)?.watchedEpisodes == [1, 2])
    }

    @Test func anUndoAfterAnEarlierPinAndMoveFailedRestoresTheMovieAsTheServerHasIt() async throws {
        let movies = MovieStore(apiClient: apiClient, undoWindow: .seconds(30))
        await movies.load()
        LibraryListProtocol.patchDelay = 0.3
        LibraryListProtocol.failsPath = "/api/v1/movies/10"

        // the pin and the move to Watched wait in the queue while the movie is removed from Watched
        await movies.setPinned(id: 10, pinned: true)
        let write = await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        await movies.toggle(id: 10, title: "Heat", posterPath: "", runtime: 0, target: .watched)
        #expect(movies.isRemovalPending(id: 10))
        await write.value
        #expect(movies.wantMovies.isEmpty)
        movies.undoRemoval(id: 10)

        // both PATCHes failed, so the movie comes back unpinned in Want, where the server still has it
        #expect(movies.wantMovies.map(\.id) == [10])
        #expect(movies.watchedMovies.isEmpty)
        #expect(!movies.isPinned(id: 10))
        #expect(!LibraryListProtocol.answered.contains { $0.hasPrefix("DELETE") })
    }
}
