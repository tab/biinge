import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

@MainActor
struct DetailsTitleTests {
    @Test(arguments: [
        (String?.none, true, DetailsPlay.notOnServer),
        // not connected asks to connect first, also for a title the library seems to lack
        (String?.none, false, DetailsPlay.connect),
        ("j1", true, DetailsPlay.play("j1")),
        ("j1", false, DetailsPlay.connect),
    ])
    func playNeedsAJellyfinIDAndAConnection(jellyfinID: String?, isConnected: Bool, expected: DetailsPlay) {
        #expect(DetailsPlay(jellyfinID: jellyfinID, isConnected: isConnected) == expected)
    }

    @Test(arguments: [
        ("j1", true, DetailsPlay.unreachable("j1")),
        // the API still says the server lacks the title, and Connect still comes first
        (String?.none, true, DetailsPlay.notOnServer),
        ("j1", false, DetailsPlay.connect),
    ])
    func anUnreachableServerKeepsTheItemToShowItsPlayDisabled(jellyfinID: String?, isConnected: Bool, expected: DetailsPlay) {
        #expect(DetailsPlay(jellyfinID: jellyfinID, isConnected: isConnected, isUnreachable: true) == expected)
    }

    @Test func aMovieOrSeriesOpensByItsTMDBID() {
        #expect(DetailsTitle(BaseItemDto(id: "m", providerIDs: ["Tmdb": "10"], type: .movie)) == .movie(10))
        #expect(DetailsTitle(BaseItemDto(id: "s", providerIDs: ["Tmdb": "20"], type: .series)) == .series(20))
    }

    @Test func anItemWithoutATMDBIDOrOfAnotherKindOpensNothing() {
        #expect(DetailsTitle(BaseItemDto(id: "m", type: .movie)) == nil)
        #expect(DetailsTitle(BaseItemDto(id: "m", providerIDs: ["Imdb": "tt1"], type: .movie)) == nil)
        #expect(DetailsTitle(BaseItemDto(id: "c", providerIDs: ["Tmdb": "30"], type: .boxSet)) == nil)
    }

    @Test func anEpisodeOpensItsSeriesByTheSeriesTMDBID() async throws {
        let service = MockJellyfinService()
        service.items["s"] = BaseItemDto(id: "s", providerIDs: ["Tmdb": "20"], type: .series)
        // the episode's own TMDB ID is the episode's, not the series'
        let episode = BaseItemDto(id: "e", providerIDs: ["Tmdb": "99"], seriesID: "s", type: .episode)

        #expect(try await DetailsTitle.resolve(episode, service: service) == .series(20))
        #expect(try await DetailsTitle.resolve(BaseItemDto(id: "n", seriesID: "s", type: .season), service: service) == .series(20))
    }

    @Test func anEpisodeOfASeriesWithoutATMDBIDOpensNothing() async throws {
        let service = MockJellyfinService()
        service.items["s"] = BaseItemDto(id: "s", type: .series)

        #expect(try await DetailsTitle.resolve(BaseItemDto(id: "e", seriesID: "s", type: .episode), service: service) == nil)
        #expect(try await DetailsTitle.resolve(BaseItemDto(id: "e", type: .episode), service: service) == nil)
    }

    @Test func aMovieResolvesWithoutAFetch() async throws {
        #expect(try await DetailsTitle.resolve(BaseItemDto(id: "m", providerIDs: ["Tmdb": "10"], type: .movie), service: MockJellyfinService()) == .movie(10))
    }

    @Test func aPlayedMovieMarksTheMovie() {
        let movie = BaseItemDto(id: "m", providerIDs: ["Tmdb": "10"], type: .movie)
        #expect(PlayedMark(movie, title: .movie(10), isWatchedMovie: { _ in false }) == .movie(10))
    }

    @Test func aPlayedEpisodeMarksItsNumbersInTheSeries() {
        let episode = BaseItemDto(id: "e", indexNumber: 4, parentIndexNumber: 2, seriesID: "s", type: .episode)
        #expect(PlayedMark(episode, title: .series(20), isWatchedMovie: { _ in false }) == .episode(series: 20, season: 2, episode: 4))
    }

    @Test func anItemWithoutATMDBIDOrEpisodeNumbersMarksNothing() {
        #expect(PlayedMark(BaseItemDto(id: "m", type: .movie), title: nil, isWatchedMovie: { _ in false }) == nil)
        #expect(PlayedMark(BaseItemDto(id: "e", seriesID: "s", type: .episode), title: .series(20), isWatchedMovie: { _ in false }) == nil)
        #expect(PlayedMark(BaseItemDto(id: "v", type: .video), title: nil, isWatchedMovie: { _ in false }) == nil)
    }

    @Test func aMovieBiingeHoldsAsWatchedMarksNothing() {
        let movie = BaseItemDto(id: "m", providerIDs: ["Tmdb": "10"], type: .movie)
        // a second write would toggle the movie out of Watched
        #expect(PlayedMark(movie, title: .movie(10), isWatchedMovie: { $0 == 10 }) == nil)
    }
}

/// The action row offers the next step for a title's kind, list and server, and its list pill names where the title is
struct DetailActionsTests {
    /// Jellyfin ticks in a minute
    private let minute = 600_000_000

    @Test func aMoviePlaysResumesOrPlaysAgainWhenItCanPlay() {
        let resume = DetailPrimary.movie(play: .play("j1"), state: .want, position: 56 * minute, runtime: 128 * minute, playedOnServer: false)
        #expect(resume == DetailPrimary(label: "Resume", detail: "1h 12m left", systemImage: "play.fill", action: .play("j1")))
        #expect(resume?.title == "Resume · 1h 12m left")
        #expect(DetailPrimary.movie(play: .play("j1"), state: .watched, position: 0, runtime: 0, playedOnServer: false)
            == DetailPrimary(label: "Play Again", detail: nil, systemImage: "arrow.counterclockwise", action: .play("j1")))
        #expect(DetailPrimary.movie(play: .play("j1"), state: nil, position: 0, runtime: 0, playedOnServer: true)?.label == "Play Again")
        #expect(DetailPrimary.movie(play: .play("j1"), state: nil, position: 0, runtime: 0, playedOnServer: false)
            == DetailPrimary(label: "Play", detail: nil, systemImage: "play.fill", action: .play("j1")))
    }

    @Test func anUnreachableServerShowsTheSamePlayDisabled() {
        let pill = DetailPrimary.movie(play: .unreachable("j1"), state: .want, position: 56 * minute, runtime: 128 * minute, playedOnServer: false)

        #expect(pill?.title == "Resume · 1h 12m left")
        #expect(pill?.action == .unreachable)
        #expect(DetailPrimary.series(play: .unreachable("e4"), state: .watching, episode: (1, 4), position: 0, caughtUp: false, playedOnServer: false)?.action
            == .unreachable)
    }

    @Test(arguments: [DetailsPlay.connect, .notOnServer])
    func aTitleThatCantPlayLeadsWithWantUntilItSitsInAList(play: DetailsPlay) {
        let add = DetailPrimary(label: "Add to Want to Watch", detail: nil, systemImage: nil, action: .move(.want))

        #expect(DetailPrimary.movie(play: play, state: nil, position: 0, runtime: 0, playedOnServer: false) == add)
        #expect(DetailPrimary.series(play: play, state: nil, episode: (1, 4), position: 0, caughtUp: false, playedOnServer: false) == add)
        #expect(DetailPrimary.movie(play: play, state: .want, position: 0, runtime: 0, playedOnServer: false) == nil)
        #expect(DetailPrimary.series(play: play, state: .watching, episode: (1, 4), position: 0, caughtUp: false, playedOnServer: false) == nil)
    }

    @Test func aSeriesPlaysItsOfferedEpisode() {
        #expect(DetailPrimary.series(play: .play("e4"), state: .watching, episode: (1, 4), position: 1, caughtUp: false, playedOnServer: false)
            == DetailPrimary(label: "Resume S1 · E4", detail: nil, systemImage: "play.fill", action: .play("e4")))
        #expect(DetailPrimary.series(play: .play("e4"), state: .watching, episode: (1, 4), position: 0, caughtUp: false, playedOnServer: false)?.label
            == "Play S1 · E4")
        // a watched show whose offer is the opener again plays it again
        #expect(DetailPrimary.series(play: .play("e1"), state: .watched, episode: (1, 1), position: 0, caughtUp: true, playedOnServer: false)
            == DetailPrimary(label: "Play Again · S1 · E1", detail: nil, systemImage: "arrow.counterclockwise", action: .play("e1")))
        #expect(DetailPrimary.series(play: .play("e1"), state: nil, episode: (1, 1), position: 0, caughtUp: true, playedOnServer: true)?.label
            == "Play Again · S1 · E1")
        // a new episode after Watched is a next step, not a replay
        #expect(DetailPrimary.series(play: .play("e9"), state: .watched, episode: (2, 1), position: 0, caughtUp: false, playedOnServer: false)?.label
            == "Play S2 · E1")
    }

    @Test func aSeriesWithNoOfferedEpisodeOnlyOffersWant() {
        #expect(DetailPrimary.series(play: .play("s"), state: nil, episode: nil, position: 0, caughtUp: false, playedOnServer: false)?.action == .move(.want))
        #expect(DetailPrimary.series(play: .play("s"), state: .watching, episode: nil, position: 0, caughtUp: false, playedOnServer: false) == nil)
    }

    @Test func aGameMovesOneListForward() {
        #expect(DetailPrimary.game(state: nil, isReleased: false) == DetailPrimary(label: "Add to Want to Play", detail: nil, systemImage: nil, action: .move(.want)))
        #expect(DetailPrimary.game(state: .want, isReleased: true)
            == DetailPrimary(label: "Mark as Playing", detail: nil, systemImage: "gamecontroller.fill", action: .move(.playing)))
        #expect(DetailPrimary.game(state: .playing, isReleased: true)
            == DetailPrimary(label: "Mark as Played", detail: nil, systemImage: "checkmark", action: .move(.played)))
        #expect(DetailPrimary.game(state: .want, isReleased: false) == nil)
        #expect(DetailPrimary.game(state: .played, isReleased: true) == nil)
    }

    @Test func theListPillNamesTheListAndPinOrOffersToAdd() {
        let watching = DetailListPill(.series, state: .watching, isPinned: true)
        #expect([watching.label, watching.systemImage] == ["Watching", "circle.lefthalf.filled"])
        #expect(watching.isPinned)
        #expect(DetailListPill(.game, state: .want, isPinned: false).label == "Want to Play")
        #expect(DetailListPill(.game, state: .playing, isPinned: false).systemImage == "gamecontroller.fill")
        #expect(DetailListPill(.movie, state: .watched, isPinned: false).systemImage == "checkmark.circle.fill")
        // a title in no list has no pin to show
        let add = DetailListPill(.movie, state: nil, isPinned: true)
        #expect([add.label, add.systemImage] == ["Add to List", "plus"])
        #expect(!add.isPinned)
    }

    @Test func eachKindListsItsListsWithTheirDescriptions() {
        let movie = DetailList.lists(.movie, server: "Living Room")
        let series = DetailList.lists(.series, server: "Living Room")
        let game = DetailList.lists(.game, server: "Living Room")

        #expect(movie.map(\.name) == ["Want to Watch", "Watched"])
        #expect(movie.map(\.summary) == ["Saved for later.", "Also marks it played on Living Room."])
        #expect(series.map(\.name) == ["Want to Watch", "Watching", "Watched"])
        #expect(series.map(\.summary) == ["Saved for later.", "Biinge follows your next episode.", "Marks every episode watched, here and on Living Room."])
        #expect(game.map(\.name) == ["Want to Play", "Playing", "Played"])
        #expect(game.map(\.summary) == ["Saved for later.", "What you’re playing now.", "Finished, or done with it. Unpins it."])
        #expect(movie.filter(\.state.isPinnable).map(\.state) == [.want])
        #expect(series.filter(\.state.isPinnable).map(\.state) == [.want, .watching])
        #expect(game.filter(\.state.isPinnable).map(\.state) == [.want, .playing])
    }
}

/// Answers the biinge details a Play outside details looks up and the series and seasons the next-episode card loads, and records every request
final class PlayResolutionProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    /// Every request as "METHOD path", in order
    nonisolated(unsafe) static var requests: [String] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return }
        Self.requests.append("\(method) \(url.path)")
        let movie = #""posterPath": "", "pinned": false, "state": "none", "overview": "", "genres": [], "credits": [], "recommendations": [], "videos": []"#
        let episode = #""posterPath": "", "runtime": 50, "overview": "", "credits": [], "videos": []"#
        // series 20 has specials and seasons 1 to 3, whose episodes carry Jellyfin IDs like "s2e1"
        let seasons = [0, 1, 2, 3].map { #"{"id": \#(200 + $0), "title": "Season \#($0)", "number": \#($0), "posterPath": "", "episodesCount": 1}"# }
        let series = #"{"id": 20, "title": "Silo", \#(movie), "seasons": [\#(seasons.joined(separator: ", "))]}"#
        let season = { (number: Int, count: Int) in
            let episodes = (1...count).map {
                #"{"id": \#(number * 10 + $0), "title": "E\#($0)", "number": \#($0), "posterPath": "", "runtime": 50, "overview": "", "jellyfinId": "s\#(number)e\#($0)"}"#
            }
            return #"{"id": \#(200 + number), "title": "Season \#(number)", "number": \#(number), "posterPath": "", "overview": "", "episodes": [\#(episodes.joined(separator: ", "))]}"#
        }
        let response = switch url.path {
        case "/api/v1/movies/10": #"{"id": 10, "title": "Heat", \#(movie), "jellyfinId": "j10"}"#
        case "/api/v1/movies/11": #"{"id": 11, "title": "Arrival", \#(movie)}"#
        case "/api/v1/series/20/season/2/episode/5": #"{"id": 205, "title": "Five", "number": 5, \#(episode), "jellyfinId": "e1"}"#
        // the library holds two copies of S2E4, so its details name neither
        case "/api/v1/series/20/season/2/episode/4": #"{"id": 204, "title": "Four", "number": 4, \#(episode)}"#
        case "/api/v1/series/20": series
        case "/api/v1/series/20/season/1": season(1, 2)
        case "/api/v1/series/20/season/2": season(2, 3)
        case "/api/v1/series/20/season/3": season(3, 1)
        default: "{}"
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
struct PlayResolutionTests {
    private let apiClient: Biinge.APIClient
    private let service = MockJellyfinService()

    init() {
        PlayResolutionProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlayResolutionProtocol.self]
        apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
        service.items["s"] = BaseItemDto(id: "s", providerIDs: ["Tmdb": "20"], type: .series)
        service.items["j10"] = BaseItemDto(id: "j10", name: "Heat", type: .movie)
        service.items["e1"] = BaseItemDto(id: "e1", name: "Five", type: .episode)
    }

    @Test func aMoviePlaysTheItemItsDetailsName() async throws {
        let card = BaseItemDto(id: "m", providerIDs: ["Tmdb": "10"], type: .movie)

        #expect(try await PlayResolution.resolve(card, service: service, apiClient: apiClient) == .play(BaseItemDto(id: "j10", name: "Heat", type: .movie)))
        #expect(PlayResolutionProtocol.requests == ["GET /api/v1/movies/10"])
    }

    @Test func aMovieWhoseDetailsNameNoItemOpensItsDetails() async throws {
        let card = BaseItemDto(id: "m", providerIDs: ["Tmdb": "11"], type: .movie)

        #expect(try await PlayResolution.resolve(card, service: service, apiClient: apiClient) == .details(.movie(11)))
    }

    @Test func anEpisodePlaysTheItemItsDetailsName() async throws {
        let card = BaseItemDto(id: "x", indexNumber: 5, parentIndexNumber: 2, seriesID: "s", type: .episode)

        #expect(try await PlayResolution.resolve(card, service: service, apiClient: apiClient) == .play(BaseItemDto(id: "e1", name: "Five", type: .episode)))
        #expect(PlayResolutionProtocol.requests == ["GET /api/v1/series/20/season/2/episode/5"])
    }

    @Test func anEpisodeWithoutNumbersOpensItsSeries() async throws {
        let card = BaseItemDto(id: "x", seriesID: "s", type: .episode)

        #expect(try await PlayResolution.resolve(card, service: service, apiClient: apiClient) == .details(.series(20)))
        #expect(PlayResolutionProtocol.requests.isEmpty)
    }

    @Test func aDuplicateEpisodeDoesNotPlayAndOpensItsSeries() async throws {
        // the card is one of the two copies, which Jellyfin would play as it is
        let card = BaseItemDto(id: "copy", indexNumber: 4, parentIndexNumber: 2, seriesID: "s", type: .episode)

        #expect(try await PlayResolution.resolve(card, service: service, apiClient: apiClient) == .details(.series(20)))
    }

    @Test func aSeriesOpensItsDetailsWithoutALookup() async throws {
        let card = BaseItemDto(id: "s", providerIDs: ["Tmdb": "20"], type: .series)

        #expect(try await PlayResolution.resolve(card, service: service, apiClient: apiClient) == .details(.series(20)))
        #expect(PlayResolutionProtocol.requests.isEmpty)
    }

    @Test func anEpisodeInsideItsSeasonLoadsOnlyThatSeason() async {
        let playing = BaseItemDto(id: "x", indexNumber: 2, parentIndexNumber: 2, seriesID: "s", type: .episode)

        let neighbors = await EpisodeNeighbors.load(playing, service: service, apiClient: apiClient)

        #expect(neighbors.previous?.episode.jellyfinID == "s2e1")
        #expect(neighbors.next?.episode.jellyfinID == "s2e3")
        #expect(PlayResolutionProtocol.requests == ["GET /api/v1/series/20", "GET /api/v1/series/20/season/2"])
    }

    @Test func aSeasonsFirstAndLastEpisodesLoadTheSeasonBeforeAndAfter() async {
        let opener = BaseItemDto(id: "x", indexNumber: 1, parentIndexNumber: 2, seriesID: "s", type: .episode)
        let closer = BaseItemDto(id: "y", indexNumber: 3, parentIndexNumber: 2, seriesID: "s", type: .episode)

        let before = await EpisodeNeighbors.load(opener, service: service, apiClient: apiClient)
        let after = await EpisodeNeighbors.load(closer, service: service, apiClient: apiClient)

        #expect(before.previous?.season == 1)
        #expect(before.previous?.episode.jellyfinID == "s1e2")
        #expect(after.next?.season == 3)
        #expect(after.next?.episode.jellyfinID == "s3e1")
        // the specials never load, and neither does a season the episode doesn't border
        #expect(PlayResolutionProtocol.requests == [
            "GET /api/v1/series/20", "GET /api/v1/series/20/season/2", "GET /api/v1/series/20/season/1",
            "GET /api/v1/series/20", "GET /api/v1/series/20/season/2", "GET /api/v1/series/20/season/3",
        ])
    }

    @Test func aMovieHasNoNeighborsAndLoadsNothing() async {
        let movie = BaseItemDto(id: "m", providerIDs: ["Tmdb": "10"], type: .movie)

        let neighbors = await EpisodeNeighbors.load(movie, service: service, apiClient: apiClient)

        #expect(neighbors.previous == nil)
        #expect(neighbors.next == nil)
        #expect(PlayResolutionProtocol.requests.isEmpty)
    }

    @Test func anItemWithoutATMDBIDDoesNothing() async throws {
        #expect(try await PlayResolution.resolve(BaseItemDto(id: "m", type: .movie), service: service, apiClient: apiClient) == .nothing)
        #expect(PlayResolutionProtocol.requests.isEmpty)
    }
}
