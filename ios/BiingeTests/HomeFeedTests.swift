import Foundation
import Testing
@testable import Biinge

/// Answers Home's Jellyfin lists with one movie each, named by its list (a list of items by the types it asks for), or the body the running test sets for the request, or `failStatus` while it sets fails; records each item list as "types/limit" and each request by its key, and answers the movies-only list last
final class HomeFeedProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var fails = false
    nonisolated(unsafe) static var failStatus = 500
    /// The body each request key answers in place of its list's movie (a key is the path, with "?seriesId" for a series' next up lookup; behind the lock, as the URLProtocol threads read while a test writes)
    static var bodies: [String: String] {
        get { lock.withLock { replaced } }
        set { lock.withLock { replaced = newValue } }
    }
    /// The next request of each key here takes its answer as it arrives, then waits until the test sets released
    static var holdOnce: Set<String> {
        get { lock.withLock { holding } }
        set { lock.withLock { holding = newValue } }
    }
    static var released: Bool {
        get { lock.withLock { isReleased } }
        set { lock.withLock { isReleased = newValue } }
    }
    /// Every request's key, in the order they arrive
    static var keys: [String] {
        get { lock.withLock { seen } }
        set { lock.withLock { seen = newValue } }
    }
    /// Every item list as "types/limit", in the order they arrive (behind a lock, as the URLProtocol threads append while a test reads)
    static var lists: [String] {
        get { lock.withLock { recorded } }
        set { lock.withLock { recorded = newValue } }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [String] = []
    nonisolated(unsafe) private static var replaced: [String: String] = [:]
    nonisolated(unsafe) private static var holding: Set<String> = []
    nonisolated(unsafe) private static var isReleased = false
    nonisolated(unsafe) private static var seen: [String] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let id: String
        switch url.path {
        case "/UserItems/Resume":
            id = "resume"
        case "/Shows/NextUp":
            id = "next"
        default:
            // the item types may come as one comma list or as a repeated key
            let types = query.filter { $0.name == "includeItemTypes" }.flatMap { ($0.value ?? "").components(separatedBy: ",") }.joined(separator: ",")
            let limit = query.first { $0.name == "limit" }?.value ?? ""
            Self.lock.withLock { Self.recorded.append("\(types)/\(limit)") }
            id = types
        }
        let key = url.path == "/Shows/NextUp" && query.contains { $0.name == "seriesId" } ? "\(url.path)?seriesId" : url.path
        let (body, held) = Self.lock.withLock {
            Self.seen.append(key)
            return (Self.replaced[key], Self.holding.remove(key) != nil)
        }
        let status = Self.fails ? Self.failStatus : 200
        let answerBody = Self.fails ? "" : body ?? #"{"Items": [{"Id": "\#(id)", "Name": "\#(id)", "Type": "Movie", "UserData": {"Key": "item", "Played": false}}], "TotalRecordCount": 1}"#
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        response = (http, Data(answerBody.utf8))
        guard !held else { return waitForRelease() }
        guard id == "Movie" else { return answer() }
        // the movies answer after the series, so the rows' order can't follow the answers' (on this protocol's run loop, which keeps the other lists answering meanwhile)
        perform(#selector(answer), with: nil, afterDelay: 0.3, inModes: [.common])
    }

    /// The answer startLoading prepared
    private var response: (HTTPURLResponse, Data)?

    /// Answers once the test releases the request, checking again on this protocol's run loop so the other requests keep answering meanwhile
    @objc private func waitForRelease() {
        guard Self.released else {
            perform(#selector(waitForRelease), with: nil, afterDelay: 0.01, inModes: [.common])
            return
        }
        answer()
    }

    @objc private func answer() {
        guard let (http, body) = response else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// Home needs a connected connection, which comes from the Keychain, so these tests share JellyfinConnectionTests' serialized Keychain runs
extension JellyfinConnectionTests {
    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func theHomeLoadFillsEachRow() async throws {
        try await withHomeConnection { connection in
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            await feed.load()

            let rows = try #require(feed.rows)
            #expect(rows.continueWatching.map(\.id) == ["resume"])
            #expect(rows.nextUp.map(\.id) == ["next"])
            #expect(rows.recentlyAdded.map { $0.items.map(\.id) } == [["Movie,Series"]])
            #expect(rows.collections.map(\.id) == ["BoxSet"])
            #expect(feed.failure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func theRecentlyAddedListsKeepTheirOrderAndLimits() async throws {
        try await withHomeConnection { connection in
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAddedMovies, 9), (.recentlyAddedSeries, 20)])

            await feed.load()

            let rows = try #require(feed.rows)
            #expect(rows.recentlyAdded.map { $0.items.map(\.id) } == [["Movie"], ["Series"]])
            #expect(Set(HomeFeedProtocol.lists) == ["Movie/9", "Series/20", "BoxSet/20"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailedFirstLoadTakesTheScreenAndAFailedReloadKeepsTheRows() async throws {
        try await withHomeConnection { connection in
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])
            HomeFeedProtocol.fails = true

            await feed.load()
            #expect(feed.rows == nil)
            #expect(feed.failure != nil)

            HomeFeedProtocol.fails = false
            await feed.load()
            #expect(feed.failure == nil)
            HomeFeedProtocol.fails = true
            await feed.load()

            #expect(feed.rows?.nextUp.map(\.id) == ["next"])
            #expect(feed.reloadFailure != nil)
            #expect(feed.failure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aWatchedMarkHidesItsTitleAtOnceAndFromEveryLoad() async throws {
        try await withHomeConnection { connection in
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])
            await feed.load()
            connection.setWatched(itemID: "resume", watched: true)
            connection.setWatched(itemID: "next", watched: true)
            HomeFeedProtocol.fails = true

            // the reload fails, so only the hide changed the rows
            await feed.hideWatched()

            #expect(feed.rows?.continueWatching.isEmpty == true)
            #expect(feed.rows?.nextUp.isEmpty == true)
            #expect(feed.rows?.collections.map(\.id) == ["BoxSet"])
            // Jellyfin still reports them, and the next load drops them too
            HomeFeedProtocol.fails = false
            await feed.load()
            #expect(feed.rows?.continueWatching.isEmpty == true)
            #expect(feed.rows?.nextUp.isEmpty == true)
            #expect(feed.reloadFailure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func eachHeroFillsInItsPlayAndDetailsFromItsLookup() async throws {
        try await withHomeConnection { connection in
            HomeFeedProtocol.bodies = Self.heroBodies
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            await feed.load()

            #expect(feed.heroes.map(\.item.id) == ["episode-1", "series-2"])
            #expect(feed.heroTitles == ["episode-1": .series(100)])
            #expect(feed.heroNextUps.mapValues(\.id) == ["series-2": "next-2"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aHeroWithoutAnItemIDLooksNothingUp() async throws {
        try await withHomeConnection { connection in
            HomeFeedProtocol.bodies = ["/UserItems/Resume": #"{"Items": [{"Name": "E", "Type": "Episode", "SeriesId": "series-1"}], "TotalRecordCount": 1}"#]
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            await feed.load()

            #expect(feed.heroes.count == 1)
            #expect(!HomeFeedProtocol.keys.contains("/Items/series-1"))
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aLookupANewerLoadOvertookPublishesNothing() async throws {
        try await withHomeConnection { connection in
            HomeFeedProtocol.bodies = Self.heroBodies
            HomeFeedProtocol.bodies["/Shows/NextUp?seriesId"] = #"{"Items": [{"Id": "stale"}], "TotalRecordCount": 1}"#
            HomeFeedProtocol.holdOnce = ["/Shows/NextUp?seriesId"]
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            let first = Task { await feed.load() }
            try await Self.waitForHomeRequest("/Shows/NextUp?seriesId")
            HomeFeedProtocol.bodies = Self.heroBodies
            await feed.load()
            HomeFeedProtocol.released = true
            await first.value

            #expect(feed.heroNextUps["series-2"]?.id == "next-2")
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aWatchedMarkThatLandsDuringALookupKeepsItsEpisodeOffThePlay() async throws {
        try await withHomeConnection { connection in
            HomeFeedProtocol.bodies = Self.heroBodies
            HomeFeedProtocol.holdOnce = ["/Shows/NextUp?seriesId"]
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            let load = Task { await feed.load() }
            try await Self.waitForHomeRequest("/Shows/NextUp?seriesId")
            connection.setWatched(itemID: "next-2", watched: true)
            HomeFeedProtocol.released = true
            await load.value

            #expect(feed.heroNextUps.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func rowsANewerLoadOvertookPublishNothing() async throws {
        try await withHomeConnection { connection in
            HomeFeedProtocol.holdOnce = ["/UserItems/Resume"]
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            let first = Task { await feed.load() }
            try await Self.waitForHomeRequest("/UserItems/Resume")
            HomeFeedProtocol.bodies = ["/UserItems/Resume": #"{"Items": [{"Id": "fresh", "Type": "Movie"}], "TotalRecordCount": 1}"#]
            await feed.load()
            HomeFeedProtocol.released = true
            await first.value

            #expect(feed.rows?.continueWatching.map(\.id) == ["fresh"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailureANewerLoadOvertookShowsNoError() async throws {
        try await withHomeConnection { connection in
            HomeFeedProtocol.fails = true
            HomeFeedProtocol.holdOnce = ["/UserItems/Resume"]
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            let first = Task { await feed.load() }
            try await Self.waitForHomeRequest("/UserItems/Resume")
            HomeFeedProtocol.fails = false
            await feed.load()
            HomeFeedProtocol.released = true
            await first.value

            #expect(feed.rows != nil)
            #expect(feed.reloadFailure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aLoadTheScreenLeftIsNoHomeFailure() async throws {
        try await withHomeConnection { connection in
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            let load = Task { await feed.load() }
            load.cancel()
            await load.value

            #expect(feed.failure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRevokedTokenDisconnectsHomeWithoutAnError() async throws {
        try await withHomeConnection { connection in
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])
            HomeFeedProtocol.fails = true
            HomeFeedProtocol.failStatus = 401

            await feed.load()

            #expect(!connection.isConnected)
            #expect(feed.failure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func reloadClearsTheRowsSoItsFailureTakesTheScreen() async throws {
        try await withHomeConnection { connection in
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])
            await feed.load()
            HomeFeedProtocol.fails = true

            await feed.reload()

            #expect(feed.rows == nil)
            #expect(feed.failure != nil)
            #expect(feed.reloadFailure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFeedWithoutRowsOrAConnectionSendsNothing() async throws {
        try await withHomeConnection { connection in
            let feed = HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)])

            await feed.hideWatched()
            #expect(HomeFeedProtocol.keys.isEmpty)

            await connection.disconnect()
            HomeFeedProtocol.keys = []
            await feed.load()

            #expect(HomeFeedProtocol.keys.isEmpty)
            #expect(feed.rows == nil)
            #expect(feed.heroes.isEmpty)
        }
    }

    /// A resumed episode of series 100 and a recently added series with a next up episode
    private static let heroBodies = [
        "/UserItems/Resume": #"{"Items": [{"Id": "episode-1", "Type": "Episode", "SeriesId": "series-1"}], "TotalRecordCount": 1}"#,
        "/Items": #"{"Items": [{"Id": "series-2", "Type": "Series", "ProviderIds": {"Tmdb": "200"}}], "TotalRecordCount": 1}"#,
        "/Items/series-1": #"{"Id": "series-1", "Type": "Series", "ProviderIds": {"Tmdb": "100"}}"#,
        "/Shows/NextUp?seriesId": #"{"Items": [{"Id": "next-2", "Type": "Episode"}], "TotalRecordCount": 1}"#,
    ]

    /// Waits up to 5 s for the request to reach the stub protocol
    private static func waitForHomeRequest(_ key: String) async throws {
        var waited = 0
        while !HomeFeedProtocol.keys.contains(key), waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        try #require(HomeFeedProtocol.keys.contains(key))
    }

    /// Runs the body with a connection the Keychain restores, whose Jellyfin calls HomeFeedProtocol answers from a fresh scenario
    private func withHomeConnection(_ body: (JellyfinConnection) async throws -> Void) async throws {
        HomeFeedProtocol.fails = false
        HomeFeedProtocol.failStatus = 500
        HomeFeedProtocol.lists = []
        HomeFeedProtocol.bodies = [:]
        HomeFeedProtocol.holdOnce = []
        HomeFeedProtocol.released = false
        HomeFeedProtocol.keys = []
        let keychain = Keychain()
        keychain.save("https://jellyfin.example.com", for: .jellyfinServer)
        keychain.save("user-id", for: .jellyfinUserID)
        keychain.save("token", for: .jellyfinToken)
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
        }
        let stub = URLSessionConfiguration.ephemeral
        stub.protocolClasses = [HomeFeedProtocol.self]
        let connection = JellyfinConnection(sessionConfiguration: stub, deviceID: { "test" })
        try #require(connection.isConnected)
        try await body(connection)
    }
}
