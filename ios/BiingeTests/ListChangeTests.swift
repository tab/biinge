import Foundation
import Testing
@testable import Biinge

/// Answers the biinge lists with movie 10 in Want (Watched once a PATCH has moved it), series 20 and game 30 in Want, and every write with a server error while the running test sets fails
final class ListChangeProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var fails = false
    /// Whether a PATCH has moved the movie to Watched
    nonisolated(unsafe) static var moved = false
    /// Every write as "METHOD path", in order
    nonisolated(unsafe) static var writes: [String] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return }
        let isWrite = method != "GET"
        if isWrite { Self.writes.append("\(method) \(url.path)") }
        if method == "PATCH", url.path == "/api/v1/movies/10", !Self.fails { Self.moved = true }
        let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "type" }?.value
        let movie = #"{"id": 10, "title": "Heat", "posterPath": "", "pinned": false, "state": "\#(Self.moved ? "watched" : "want")", "jellyfinId": "j10"}"#
        let series = #"{"id": 20, "title": "Silo", "posterPath": "", "pinned": false, "state": "want", "episodesCount": 10, "watchedEpisodesCount": 0}"#
        let game = #"{"id": 30, "title": "Astro Bot", "posterPath": "", "pinned": false, "state": "want"}"#
        let item: String? = switch (url.path, type) {
        case ("/api/v1/movies", "want"): Self.moved ? nil : movie
        case ("/api/v1/movies", "watched"): Self.moved ? movie : nil
        case ("/api/v1/series", "want"): series
        case ("/api/v1/games", "want"): game
        default: nil
        }
        let body = isWrite
            ? #"{"id": 10, "title": "Heat", "posterPath": "", "pinned": false, "state": "watched", "overview": "", "genres": [], "platforms": [], "#
                + #""credits": [], "recommendations": [], "videos": [], "seasons": []}"#
            : #"{"data": [\#(item ?? "")], "meta": {"page": 1, "per": 10000, "total": \#(item == nil ? 0 : 1)}}"#
        let status = isWrite && Self.fails ? 500 : 200
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((status == 500 ? #"{"error": "internal error"}"# : body).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct ListChangeTests {
    private let apiClient: Biinge.APIClient

    init() {
        ListChangeProtocol.fails = false
        ListChangeProtocol.moved = false
        ListChangeProtocol.writes = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ListChangeProtocol.self]
        apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
    }

    @Test func aMoveIntoWatchedWritesTheStoreAndMirrorsTheMarkToJellyfin() async throws {
        let store = MovieStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()
        let connection = JellyfinConnection(sessionConfiguration: .ephemeral, deviceID: { "test" })

        let change = try #require(await store.change(
            id: 10, title: "Heat", posterPath: "", runtime: 120, jellyfinID: "j10", to: .watched, connection: connection
        ))

        #expect(store.currentState(id: 10) == .watched)
        #expect(change.toast?.message == "Moved to Watched")
        // Home hides the movie before the write lands
        #expect(connection.watchedIDs.contains("j10"))
        #expect(await change.outcome.value == nil)
        #expect(ListChangeProtocol.writes == ["PATCH /api/v1/movies/10"])
        #expect(connection.watchedIDs.contains("j10"))
    }

    @Test func aFailedMoveGivesTheFailureToastAndTakesTheMirrorBack() async throws {
        ListChangeProtocol.fails = true
        let store = MovieStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()
        let connection = JellyfinConnection(sessionConfiguration: .ephemeral, deviceID: { "test" })

        let change = try #require(await store.change(
            id: 10, title: "Heat", posterPath: "", runtime: 120, jellyfinID: "j10", to: .watched, connection: connection
        ))
        let failure = await change.outcome.value

        #expect(failure?.message == "Couldn’t add Heat to Watched")
        #expect(store.currentState(id: 10) == .want)
        #expect(!connection.watchedIDs.contains("j10"))
    }

    @Test func aFailedRemovalGivesTheRemovalFailureToast() async throws {
        ListChangeProtocol.fails = true
        let store = MovieStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(id: 10, title: "Heat", posterPath: "", runtime: 120, jellyfinID: "j10", to: nil, connection: nil))

        #expect(change.toast?.message == "Removed from Want to Watch")
        #expect(await change.outcome.value?.message == "Couldn’t remove Heat")
    }

    @Test func aGameRemovalThatFailsSaysSo() async throws {
        ListChangeProtocol.fails = true
        let store = GameStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, to: nil))

        #expect(change.toast?.message == "Removed from Want to Play")
        #expect(await change.outcome.value?.message == "Couldn’t remove Astro Bot")
    }

    @Test func aFailedSeriesRemovalGivesTheRemovalFailureToast() async throws {
        ListChangeProtocol.fails = true
        let store = SeriesStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(
            id: 20, title: "Silo", posterPath: "", created: (1, 10, ""), jellyfinID: "s20", to: nil, connection: nil
        ))

        #expect(change.toast?.message == "Removed from Want to Watch")
        #expect(await change.outcome.value?.message == "Couldn’t remove Silo")
    }

    @Test func aFailedSeriesMoveGivesTheFailureToast() async throws {
        ListChangeProtocol.fails = true
        let store = SeriesStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(
            id: 20, title: "Silo", posterPath: "", created: (1, 10, ""), jellyfinID: "s20", to: .watching, connection: nil
        ))

        #expect(change.toast?.message == "Moved to Watching")
        #expect(await change.outcome.value?.message == "Couldn’t add Silo to Watching")
        #expect(store.currentState(id: 20) == .want)
    }

    @Test func aSeriesChangeToItsOwnListDoesNothing() async {
        let store = SeriesStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        #expect(await store.change(id: 20, title: "Silo", posterPath: "", created: (1, 10, ""), jellyfinID: "s20", to: .want, connection: nil) == nil)
        #expect(ListChangeProtocol.writes.isEmpty)
    }

    @Test func aSeriesMoveIntoWatchedWithoutAConnectionNamesNoServer() async throws {
        // the failed write ends the change early, and the toast's line is set before it
        ListChangeProtocol.fails = true
        let store = SeriesStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(
            id: 20, title: "Silo", posterPath: "", created: (1, 10, ""), jellyfinID: "s20", to: .watched, connection: nil
        ))
        _ = await change.outcome.value

        #expect(change.toast?.message == "Moved to Watched")
        #expect(change.toast?.sub == nil)
    }

    @Test func aChangeToTheListTheTitleSitsInDoesNothing() async {
        let store = MovieStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        #expect(await store.change(id: 10, title: "Heat", posterPath: "", runtime: 120, jellyfinID: "j10", to: .want, connection: nil) == nil)
        #expect(ListChangeProtocol.writes.isEmpty)
    }

    @Test func aMoveIntoWatchedWithoutAConnectionNamesNoServer() async throws {
        let store = MovieStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(
            id: 10, title: "Heat", posterPath: "", runtime: 120, jellyfinID: "j10", to: .watched, connection: nil
        ))

        #expect(change.toast?.sub == nil)
        _ = await change.outcome.value
    }

    @Test func aSeriesMoveThatLandsEndsWithNoFailure() async throws {
        let store = SeriesStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(
            id: 20, title: "Silo", posterPath: "", created: (1, 10, ""), jellyfinID: "s20", to: .watching, connection: nil
        ))

        #expect(await change.outcome.value == nil)
        #expect(ListChangeProtocol.writes == ["PATCH /api/v1/series/20"])
    }

    @Test func aGameMoveWritesTheStore() async throws {
        let store = GameStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, to: .played))

        #expect(change.toast?.message == "Moved to Played")
        #expect(store.currentState(id: 30) == .played)
        #expect(await change.outcome.value == nil)
        // a game's outcome doesn't wait for its move, whose write must end before the next test starts
        var waited = 0
        while ListChangeProtocol.writes.isEmpty, waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        #expect(ListChangeProtocol.writes == ["PATCH /api/v1/games/30"])
    }

    @Test func aGameRemovalThatLandsEndsWithNoFailure() async throws {
        let store = GameStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        let change = try #require(await store.change(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, to: nil))

        #expect(await change.outcome.value == nil)
        #expect(ListChangeProtocol.writes == ["DELETE /api/v1/games/30"])
    }

    @Test func aGameChangeToItsOwnListDoesNothing() async {
        let store = GameStore(apiClient: apiClient, undoWindow: .zero)
        await store.load()

        #expect(await store.change(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, to: .want) == nil)
        #expect(ListChangeProtocol.writes.isEmpty)
    }

    // the window here only keeps the removal pending, and each change reads the platform's own window to offer Undo
    @Test(.enabled(if: Toast.undoWindow > .zero, "Apple TV's toast takes no focus, so it has no Undo"))
    func undoOnAMovieRemovalPutsItBackAndSendsNothing() async throws {
        let store = MovieStore(apiClient: apiClient, undoWindow: .seconds(60))
        await store.load()

        let change = try #require(await store.change(id: 10, title: "Heat", posterPath: "", runtime: 120, jellyfinID: nil, to: nil, connection: nil))
        let toast = try #require(change.toast)

        #expect(toast.canUndo?() == true)
        toast.undo?()

        #expect(toast.canUndo?() == false)
        #expect(store.currentState(id: 10) == .want)
        #expect(await change.outcome.value == nil)
        #expect(ListChangeProtocol.writes.isEmpty)
    }

    @Test(.enabled(if: Toast.undoWindow > .zero, "Apple TV's toast takes no focus, so it has no Undo"))
    func undoOnASeriesRemovalPutsItBackAndSendsNothing() async throws {
        let store = SeriesStore(apiClient: apiClient, undoWindow: .seconds(60))
        await store.load()

        let change = try #require(await store.change(
            id: 20, title: "Silo", posterPath: "", created: (1, 10, ""), jellyfinID: nil, to: nil, connection: nil
        ))
        let toast = try #require(change.toast)

        #expect(toast.canUndo?() == true)
        toast.undo?()

        #expect(toast.canUndo?() == false)
        #expect(store.currentState(id: 20) == .want)
        #expect(await change.outcome.value == nil)
        #expect(ListChangeProtocol.writes.isEmpty)
    }

    @Test(.enabled(if: Toast.undoWindow > .zero, "Apple TV's toast takes no focus, so it has no Undo"))
    func undoOnAGameRemovalPutsItBackAndSendsNothing() async throws {
        let store = GameStore(apiClient: apiClient, undoWindow: .seconds(60))
        await store.load()

        let change = try #require(await store.change(id: 30, title: "Astro Bot", posterPath: "", runtime: 0, to: nil))
        let toast = try #require(change.toast)

        #expect(toast.canUndo?() == true)
        toast.undo?()

        #expect(toast.canUndo?() == false)
        #expect(store.currentState(id: 30) == .want)
        #expect(await change.outcome.value == nil)
        #expect(ListChangeProtocol.writes.isEmpty)
    }
}

// a connected connection comes from the Keychain, so this test shares JellyfinConnectionTests' serialized Keychain runs and stub
extension JellyfinConnectionTests {
    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aMoveIntoWatchedNamesTheServerItAlsoMarksPlayed() async throws {
        let keychain = Keychain()
        keychain.save("https://jellyfin.example.com", for: .jellyfinServer)
        keychain.save("user-id", for: .jellyfinUserID)
        keychain.save("token", for: .jellyfinToken)
        keychain.save("Living Room", for: .jellyfinServerName)
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
            keychain.delete(.jellyfinServerName)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        try #require(connection.isConnected)
        let store = MovieStore(apiClient: apiClient, undoWindow: .zero)

        let change = try #require(await store.change(
            id: 11, title: "Arrival", posterPath: "", runtime: 116, jellyfinID: "j11", to: .watched, connection: connection
        ))
        // the stub's answer to the add doesn't matter, but the write ends before the next test starts
        _ = await change.outcome.value

        #expect(change.toast?.sub == "Also marked played on Living Room")
    }

    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aSeriesMoveIntoWatchedNamesTheServerItAlsoMarksPlayed() async throws {
        let keychain = Keychain()
        keychain.save("https://jellyfin.example.com", for: .jellyfinServer)
        keychain.save("user-id", for: .jellyfinUserID)
        keychain.save("token", for: .jellyfinToken)
        keychain.save("Living Room", for: .jellyfinServerName)
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
            keychain.delete(.jellyfinServerName)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        try #require(connection.isConnected)
        let store = SeriesStore(apiClient: apiClient, undoWindow: .zero)

        let change = try #require(await store.change(
            id: 21, title: "Severance", posterPath: "", created: (2, 19, "Returning Series"), jellyfinID: "s21", to: .watched, connection: connection
        ))
        // the stub's answer to the add doesn't matter, but the write ends before the next test starts
        _ = await change.outcome.value

        #expect(change.toast?.sub == "Also marked played on Living Room")
    }

    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aMoveIntoWatchedOnAServerWithoutANameSaysServer() async throws {
        let keychain = Keychain()
        keychain.save("https://jellyfin.example.com", for: .jellyfinServer)
        keychain.save("user-id", for: .jellyfinUserID)
        keychain.save("token", for: .jellyfinToken)
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        try #require(connection.isConnected)
        let movies = MovieStore(apiClient: apiClient, undoWindow: .zero)
        let series = SeriesStore(apiClient: apiClient, undoWindow: .zero)

        let movie = try #require(await movies.change(
            id: 11, title: "Arrival", posterPath: "", runtime: 116, jellyfinID: "j11", to: .watched, connection: connection
        ))
        let show = try #require(await series.change(
            id: 21, title: "Severance", posterPath: "", created: (2, 19, "Returning Series"), jellyfinID: "s21", to: .watched, connection: connection
        ))
        // a title the server doesn't hold marks nothing played there
        let unheldMovie = try #require(await movies.change(
            id: 12, title: "Dune", posterPath: "", runtime: 155, jellyfinID: nil, to: .watched, connection: connection
        ))
        let unheldShow = try #require(await series.change(
            id: 22, title: "Andor", posterPath: "", created: (2, 24, "Ended"), jellyfinID: nil, to: .watched, connection: connection
        ))
        // the stub's answer to the adds doesn't matter, but the writes end before the next test starts
        _ = await movie.outcome.value
        _ = await show.outcome.value
        _ = await unheldMovie.outcome.value
        _ = await unheldShow.outcome.value

        #expect(movie.toast?.sub == "Also marked played on server")
        #expect(show.toast?.sub == "Also marked played on server")
        #expect(unheldMovie.toast?.sub == nil)
        #expect(unheldShow.toast?.sub == nil)
    }
}
