import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

/// Answers season 1 of series 20 with two episodes, or with a server error while the running test sets fails
final class SeasonDetailsProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var fails = false
    /// Every request as "METHOD path", in order
    nonisolated(unsafe) static var requests: [String] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return }
        Self.requests.append("\(method) \(url.path)")
        let episode = #""posterPath": "", "runtime": 50, "overview": """#
        let episodes = #"[{"id": 101, "title": "One", "number": 1, \#(episode), "jellyfinId": "e1"}, {"id": 102, "title": "Two", "number": 2, \#(episode)}]"#
        let body = Self.fails
            ? #"{"error": "internal error"}"#
            : #"{"id": 1, "title": "Season 1", "number": 1, "posterPath": "", "overview": "", "episodes": \#(episodes)}"#
        guard let http = HTTPURLResponse(url: url, statusCode: Self.fails ? 500 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct SeasonEpisodesTests {
    private let seasons: SeasonEpisodes

    init() {
        SeasonDetailsProtocol.fails = false
        SeasonDetailsProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SeasonDetailsProtocol.self]
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
        seasons = SeasonEpisodes(apiClient: apiClient, seriesID: 20)
    }

    @Test func aFailedSeasonLoadShowsItsErrorAndRetryLoadsIt() async {
        SeasonDetailsProtocol.fails = true
        await seasons.load(1)

        #expect(seasons.episodes[1] == nil)
        #expect(seasons.failures[1] != nil)

        SeasonDetailsProtocol.fails = false
        await seasons.load(1)

        #expect(seasons.episodes[1]?.map(\.id) == [101, 102])
        #expect(seasons.failures[1] == nil)
        #expect(SeasonDetailsProtocol.requests == ["GET /api/v1/series/20/season/1", "GET /api/v1/series/20/season/1"])
    }

    @Test func aLoadedSeasonDoesNotLoadAgain() async {
        await seasons.load(1)
        await seasons.load(1)

        #expect(SeasonDetailsProtocol.requests == ["GET /api/v1/series/20/season/1"])
    }

    @Test func episodeResumeSharesMapByJellyfinID() async throws {
        let service = MockJellyfinService()
        service.episodes["s/1"] = [
            BaseItemDto(id: "e1", userData: UserItemDataDto(key: "k", playbackPositionTicks: 600_000_000, playedPercentage: 25)),
        ]
        await seasons.load(1)
        try await seasons.loadShares(season: 1, seriesItemID: "s", service: service)
        let episodes = try #require(seasons.episodes[1])

        // One is Jellyfin's e1, and Two has no single Jellyfin item
        #expect(episodes.map { seasons.share($0) } == [0.25, nil])
    }
}
