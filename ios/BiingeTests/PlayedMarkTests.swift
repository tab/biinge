import Foundation
import Testing
@testable import Biinge

/// Answers the biinge calls a played mark makes from the running test's scenario, and records every request
final class PlayedMarkProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    /// Whether the season details report episode 4 as watched
    nonisolated(unsafe) static var episodeWatched = false
    /// Every request as "METHOD path", in order
    nonisolated(unsafe) static var requests: [String] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return }
        Self.requests.append("\(method) \(url.path)")
        let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "type" }?.value
        let response = switch (method, url.path) {
        case ("GET", "/api/v1/movies"):
            // the store holds movie 10 as watched and movie 12 as want
            switch type {
            case "watched":
                #"{"data": [{"id": 10, "title": "Heat", "posterPath": "", "pinned": false, "state": "watched"}], "meta": {"page": 1, "per": 10000, "total": 1}}"#
            case "want":
                #"{"data": [{"id": 12, "title": "Ronin", "posterPath": "", "pinned": false, "state": "want"}], "meta": {"page": 1, "per": 10000, "total": 1}}"#
            default:
                #"{"data": [], "meta": {"page": 1, "per": 10000, "total": 0}}"#
            }
        case ("GET", "/api/v1/movies/10"):
            #"{"id": 10, "title": "Heat", "posterPath": "", "pinned": false, "state": "watched", "overview": "", "genres": [], "credits": [], "recommendations": [], "videos": []}"#
        case ("GET", "/api/v1/movies/11"), ("POST", "/api/v1/movies"):
            #"{"id": 11, "title": "Arrival", "posterPath": "/a.jpg", "pinned": false, "state": "watched", "overview": "", "genres": [], "credits": [], "recommendations": [], "videos": []}"#
        case ("GET", "/api/v1/series/20"):
            #"""
            {"id": 20, "title": "Show", "posterPath": "", "pinned": false, "state": "watching", "overview": "", "genres": [], "credits": [], "recommendations": [], "videos": [],
             "seasons": [{"id": 200, "title": "Season 2", "number": 2, "posterPath": "", "episodesCount": 8}]}
            """#
        case ("GET", "/api/v1/series/20/season/2"):
            #"""
            {"id": 200, "title": "Season 2", "number": 2, "posterPath": "", "overview": "",
             "episodes": [{"id": 2004, "title": "Four", "number": 4, "posterPath": "", "overview": "", "runtime": 50, "watched": \#(Self.episodeWatched)}]}
            """#
        case ("POST", "/api/v1/series/20/seasons/200/episodes/2004/watched"), ("GET", "/api/v1/series/20/progress"):
            #"{"id": 20, "state": "watching", "trackedState": "watching", "watchedSeasons": [], "watchedEpisodes": [2004]}"#
        default:
            "{}"
        }
        guard let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct PlayedMarkTests {
    private let apiClient: Biinge.APIClient

    init() {
        PlayedMarkProtocol.episodeWatched = false
        PlayedMarkProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlayedMarkProtocol.self]
        apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
    }

    @Test func aTitleTakesItsStateOnlyFromItsOwnKindsLists() async {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()
        let series = SeriesStore(apiClient: apiClient)
        series.apply(WatchProgress(id: 20, state: .watched, trackedState: .watched, watchedSeasons: [], watchedEpisodes: []),
                    id: 20, title: "Show", posterPath: "", episodesCount: 8, pinned: false)
        series.apply(WatchProgress(id: 21, state: .want, trackedState: .want, watchedSeasons: [], watchedEpisodes: []),
                    id: 21, title: "Later", posterPath: "", episodesCount: 8, pinned: false)

        #expect(DetailsTitle.movie(10).state(movies: movies, series: series) == .watched)
        #expect(DetailsTitle.movie(12).state(movies: movies, series: series) == .want)
        #expect(DetailsTitle.series(20).state(movies: movies, series: series) == .watched)
        #expect(DetailsTitle.series(21).state(movies: movies, series: series) == .want)
        // the same IDs of the other kind aren't in its list
        #expect(DetailsTitle.series(10).state(movies: movies, series: series) == nil)
        #expect(DetailsTitle.movie(20).state(movies: movies, series: series) == nil)
    }

    @Test func aTitleFollowsTheLiveStoresWhateverAResponseSaid() {
        let movies = MovieStore(apiClient: apiClient)
        let series = SeriesStore(apiClient: apiClient)
        #expect(DetailsTitle.series(20).state(movies: movies, series: series) == nil)

        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: []),
                    id: 20, title: "Show", posterPath: "", episodesCount: 8, pinned: false)
        #expect(DetailsTitle.series(20).state(movies: movies, series: series) == .watching)

        series.apply(WatchProgress(id: 20, state: .watched, trackedState: .watched, watchedSeasons: [], watchedEpisodes: []),
                    id: 20, title: "Show", posterPath: "", episodesCount: 8, pinned: false)
        #expect(DetailsTitle.series(20).state(movies: movies, series: series) == .watched)
    }

    @Test func firstLoadsDuringOneShareItsFetch() async {
        let movies = MovieStore(apiClient: apiClient)

        async let first: Void = movies.loadIfNeeded()
        async let second: Void = movies.loadIfNeeded()
        _ = await (first, second)

        // one load asks for the Want and Watched lists, and the later caller still waits for them
        #expect(PlayedMarkProtocol.requests.filter { $0 == "GET /api/v1/movies" }.count == 2)
        #expect(movies.currentState(id: 10) == .watched)
    }

    @Test func aMovieTheStoreHoldsAsWatchedWritesNothing() async throws {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()
        #expect(movies.currentState(id: 10) == .watched)
        PlayedMarkProtocol.requests = []

        try await PlayedMark.movie(10).write(apiClient: apiClient, movies: movies, series: SeriesStore(apiClient: apiClient))

        // a toggle would have taken the movie out of Watched before its DELETE went out
        #expect(movies.currentState(id: 10) == .watched)
        #expect(PlayedMarkProtocol.requests == ["GET /api/v1/movies/10"])
    }

    @Test func anUntrackedMovieJoinsWatchedWithBiingesTitle() async throws {
        let movies = MovieStore(apiClient: apiClient)
        await movies.load()

        try await PlayedMark.movie(11).write(apiClient: apiClient, movies: movies, series: SeriesStore(apiClient: apiClient))

        #expect(movies.currentState(id: 11) == .watched)
        #expect(movies.watchedMovies.first { $0.id == 11 }?.title == "Arrival")
        // the store's write runs after toggle returns, so wait for it rather than leak it into the next test
        for _ in 0..<200 where !PlayedMarkProtocol.requests.contains("POST /api/v1/movies") {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(PlayedMarkProtocol.requests.contains("POST /api/v1/movies"))
    }

    @Test func anEpisodeTheSeasonReportsWatchedWritesNothingAndTakesTheAPIsProgress() async throws {
        PlayedMarkProtocol.episodeWatched = true
        let series = SeriesStore(apiClient: apiClient)
        // the store's progress predates the season's watched flag
        series.apply(WatchProgress(id: 20, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: []),
                    id: 20, title: "Show", posterPath: "", episodesCount: 8, pinned: false)

        try await PlayedMark.episode(series: 20, season: 2, episode: 4).write(apiClient: apiClient, movies: MovieStore(apiClient: apiClient), series: series)

        #expect(!PlayedMarkProtocol.requests.contains { $0.hasPrefix("POST") })
        #expect(PlayedMarkProtocol.requests.contains("GET /api/v1/series/20/progress"))
        #expect(series.progress(id: 20)?.watchedEpisodes == [2004])
    }

    @Test func anUnwatchedEpisodePostsOneMarkByItsTMDBIDs() async throws {
        let series = SeriesStore(apiClient: apiClient)

        try await PlayedMark.episode(series: 20, season: 2, episode: 4).write(apiClient: apiClient, movies: MovieStore(apiClient: apiClient), series: series)

        #expect(PlayedMarkProtocol.requests.filter { $0.hasPrefix("POST") } == ["POST /api/v1/series/20/seasons/200/episodes/2004/watched"])
        #expect(series.progress(id: 20)?.watchedEpisodes == [2004])
    }
}
