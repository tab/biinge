import Foundation
import Testing
@testable import Biinge

/// Answers Jellyfin's item lists from a list of the running test's total, named `item-<index>`, and its genres; records every page as "start/limit" and every genre load as "genres", and holds back a page whose start index the test holds (-1 holds the genres)
final class PagedLibraryProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var total = 70
    /// Set while every page and the genres answer `failStatus`
    nonisolated(unsafe) static var fails = false
    nonisolated(unsafe) static var failStatus = 500
    /// The start indexes whose pages wait to answer until the test removes them, so a test can act while the page is in flight (behind a lock, as the URLProtocol thread reads while a test writes)
    static var held: Set<Int> {
        get { lock.withLock { holding } }
        set { lock.withLock { holding = newValue } }
    }
    /// Every page as "start/limit", in order (behind the lock, as the URLProtocol thread appends while a test reads)
    static var pages: [String] {
        get { lock.withLock { recorded } }
        set { lock.withLock { recorded = newValue } }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var holding: Set<Int> = []
    nonisolated(unsafe) private static var recorded: [String] = []
    /// The answer startLoading prepared, and the start index it waits on
    private var response: (http: HTTPURLResponse, body: Data, start: Int)?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let start = query.first { $0.name == "startIndex" }?.value.flatMap(Int.init) ?? 0
        let limit = query.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 0
        var status = 200
        let body: String
        if url.path == "/Genres" {
            Self.lock.withLock { Self.recorded.append("genres") }
            status = Self.fails ? Self.failStatus : 200
            body = Self.fails ? "" : #"{"Items": [{"Name": "Comedy"}, {"Name": "Drama"}], "TotalRecordCount": 2}"#
        } else {
            Self.lock.withLock { Self.recorded.append("\(start)/\(limit)") }
            status = Self.fails ? Self.failStatus : 200
            let items = (start..<min(start + limit, Self.total)).map { #"{"Id": "item-\#($0)", "Name": "Item \#($0)", "Type": "Movie", "UserData": {"Key": "item", "Played": false}}"# }
            body = Self.fails ? "" : #"{"Items": [\#(items.joined(separator: ", "))], "TotalRecordCount": \#(Self.total)}"#
        }
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        response = (http, Data(body.utf8), url.path == "/Genres" ? -1 : start)
        answer()
    }

    override func stopLoading() {}

    /// Answers once the test releases the page, checking again on this protocol's run loop so the other requests keep answering meanwhile
    @objc private func answer() {
        guard let response else { return }
        if Self.held.contains(response.start) {
            perform(#selector(answer), with: nil, afterDelay: 0.01, inModes: [.common])
            return
        }
        client?.urlProtocol(self, didReceive: response.http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// the grid needs a connected connection, which comes from the Keychain, so these tests share JellyfinConnectionTests' serialized Keychain runs
extension JellyfinConnectionTests {
    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func loadMoreAppendsEachPageAndStopsAtTheEnd() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            await library.loadMore()
            #expect(library.items.count == 60)
            #expect(library.total == 70)
            await library.loadMore()
            await library.loadMore()

            #expect(library.items.map(\.id) == (0..<70).map { "item-\($0)" })
            // the third call had nothing left to load
            #expect(PagedLibraryProtocol.pages == ["0/60", "60/60"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFirstPageThatANewListReplacedIsDropped() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.held = [0]

            let load = Task { await library.load() }
            try await Self.waitForPage("0/60")
            // a new sort starts the grid over while the old sort's first page is out (both pages start at 0, so only the generation tells)
            library.list = .movies(.releaseYear, .all)
            PagedLibraryProtocol.held = []

            #expect(await load.value == false)
            #expect(library.items.isEmpty)
            #expect(library.pageFailure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aPageThatALoadOvertookIsDropped() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()
            PagedLibraryProtocol.held = [60]

            let page = Task { await library.loadMore() }
            try await Self.waitForPage("60/60")
            // a pull to refresh lands the first page again, which leaves the next index where the held page began
            #expect(await library.load())
            PagedLibraryProtocol.held = []
            await page.value

            #expect(library.items.map(\.id) == (0..<60).map { "item-\($0)" })
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aPageThatALoadBegunBeforeItOvertookIsDropped() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()
            await library.loadMore()
            PagedLibraryProtocol.held = [0, 120]

            // the load starts first, so the page after it shares its generation
            let load = Task { await library.load() }
            try await Self.waitForPage("0/60")
            let page = Task { await library.loadMore() }
            try await Self.waitForPage("120/60")
            PagedLibraryProtocol.held = [120]
            _ = await load.value
            PagedLibraryProtocol.held = []
            await page.value

            // the page began past the items the load left, so the offset tells it's stale
            #expect(library.items.map(\.id) == (0..<60).map { "item-\($0)" })
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailedFirstPageTakesTheScreenAndALaterOneShowsUnderTheItems() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            PagedLibraryProtocol.fails = true
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            await library.loadMore()
            #expect(library.failure != nil)
            #expect(library.total == nil)

            PagedLibraryProtocol.fails = false
            await library.loadMore()
            #expect(library.failure == nil)
            PagedLibraryProtocol.fails = true
            await library.loadMore()
            #expect(library.pageFailure?.isFirstPage == false)
            // a failed first-page load keeps the items too, and its Retry loads the first page
            #expect(await library.load() == false)
            #expect(library.pageFailure?.isFirstPage == true)
            #expect(library.items.count == 60)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aLoadLandsOnlyWhenWhatRunsAlongsideItDoes() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            let landed = await library.load { throw URLError(.badServerResponse) }

            #expect(!landed)
            #expect(library.items.isEmpty)
            #expect(library.failure != nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func refreshLoadsEveryPageOnScreenInOneRequest() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()
            await library.loadMore()

            await library.refresh()

            #expect(PagedLibraryProtocol.pages == ["0/60", "60/60", "0/120"])
            #expect(library.items.count == 120)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func reloadEmptiesTheGridToItsLoadingStateBeforeTheFirstPage() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.fails = true
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()
            PagedLibraryProtocol.fails = false
            PagedLibraryProtocol.pages = []
            PagedLibraryProtocol.held = [0]

            let reload = Task { await library.reload() }
            try await Self.waitForPage("0/60")
            #expect(library.failure == nil)
            #expect(library.total == nil)
            PagedLibraryProtocol.held = []
            await reload.value

            #expect(library.total == 70)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func theGenresLoadForTheGenreMenu() async throws {
        try await withPagedConnection { connection in
            let genres = PagedLibrary.Genres(connection: connection, type: .movie)

            await genres.load()

            #expect(genres.names == ["Comedy", "Drama"])
            #expect(!genres.failed)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailedGenreLoadOffersRetryAndARetryThatLandsClearsIt() async throws {
        try await withPagedConnection { connection in
            let genres = PagedLibrary.Genres(connection: connection, type: .movie)
            PagedLibraryProtocol.fails = true

            await genres.load()
            #expect(genres.failed)
            #expect(connection.isConnected)

            PagedLibraryProtocol.fails = false
            await genres.load()
            #expect(!genres.failed)
            #expect(genres.names == ["Comedy", "Drama"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aGenreLoadTheScreenLeftIsNoFailure() async throws {
        try await withPagedConnection { connection in
            let genres = PagedLibrary.Genres(connection: connection, type: .movie)

            let load = Task { await genres.load() }
            load.cancel()
            await load.value

            #expect(!genres.failed)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRevokedTokenOnTheGenresDisconnects() async throws {
        try await withPagedConnection { connection in
            let genres = PagedLibrary.Genres(connection: connection, type: .movie)
            PagedLibraryProtocol.fails = true
            PagedLibraryProtocol.failStatus = 401

            await genres.load()

            #expect(!connection.isConnected)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRevokedTokenOnALoadDisconnectsWithoutAnError() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.fails = true
            PagedLibraryProtocol.failStatus = 401

            #expect(await library.load() == false)

            #expect(!connection.isConnected)
            #expect(library.failure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRevokedTokenOnANextPageDisconnectsWithoutAnError() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.fails = true
            PagedLibraryProtocol.failStatus = 401

            await library.loadMore()

            #expect(!connection.isConnected)
            #expect(library.failure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRevokedTokenOnARefreshDisconnects() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()
            PagedLibraryProtocol.fails = true
            PagedLibraryProtocol.failStatus = 401

            await library.refresh()

            #expect(!connection.isConnected)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailedRefreshKeepsTheCardsAndTheConnection() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()
            PagedLibraryProtocol.fails = true

            await library.refresh()

            #expect(library.items.count == 60)
            #expect(library.failure == nil)
            #expect(connection.isConnected)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRefreshOfAnEmptyGridSendsNothing() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            await library.refresh()

            #expect(PagedLibraryProtocol.pages.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aPageAppendedDuringARefreshStaysAfterTheRefreshedOnes() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()
            PagedLibraryProtocol.pages = []
            PagedLibraryProtocol.held = [0]

            let refresh = Task { await library.refresh() }
            try await Self.waitForPage("0/60")
            await library.loadMore()
            PagedLibraryProtocol.held = []
            await refresh.value

            #expect(library.items.map(\.id) == (0..<120).map { "item-\($0)" })
            await library.loadMore()
            #expect(PagedLibraryProtocol.pages.last == "120/60")
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aMarkedTitleLeavesContinueWatchingUntilItsMarkFails() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .continueWatching)
            await library.loadMore()

            connection.setWatched(itemID: "item-1", watched: true)
            #expect(!library.shown.contains { $0.id == "item-1" })
            #expect(library.shownTotal == 69)
            // the card goes without a reload, and the mark outlasts one, as Jellyfin may still report the title unplayed
            await library.load()
            await library.refresh()
            #expect(!library.shown.contains { $0.id == "item-1" })

            connection.setWatched(itemID: "item-1", watched: false)
            #expect(library.shown.contains { $0.id == "item-1" })
            #expect(library.shownTotal == 70)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aMarkKeepsTheRememberedPageAndThePaging() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            await PagedLibrary(connection: connection, list: .nextUp).loadMore()
            connection.setWatched(itemID: "item-1", watched: true)
            PagedLibraryProtocol.pages = []
            PagedLibraryProtocol.held = [0]

            let library = PagedLibrary(connection: connection, list: .nextUp)
            #expect(library.shown.count == 59)
            let load = Task { await library.loadIfNeeded() }
            try await Self.waitForPage("0/60")
            await library.loadMore()
            PagedLibraryProtocol.held = []
            await load.value

            #expect(library.items.count == 120)
            #expect(library.shown.count == 119)
            #expect(connection.firstPages[.nextUp]?.items.count == 60)
            #expect(PagedLibraryProtocol.pages == ["0/60", "60/60"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aMarkLeavesUpNextAtOnceAndAFailedOneBringsItsCardBack() async throws {
        try await withPagedConnection { connection in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [PagedLibraryProtocol.self]
            let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
            let store = UpNextStore(apiClient: apiClient, connection: connection)
            await store.load()
            let hasItem = {
                store.sections.map { section -> Bool in
                    switch section {
                    case .continueWatching(let items), .nextUp(let items): items.contains { $0.id == "item-1" }
                    default: false
                    }
                }
            }
            #expect(hasItem() == [true, true])

            connection.setWatched(itemID: "item-1", watched: true)
            #expect(hasItem() == [false, false])

            connection.setWatched(itemID: "item-1", watched: false)
            #expect(hasItem() == [true, true])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aMarkLeavesAGridThatIsNotContinueWatchingOrNextUpAlone() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()

            connection.setWatched(itemID: "item-1", watched: true)

            #expect(library.shown.count == 60)
            #expect(library.shownTotal == 70)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aLoadTheScreenLeftIsNoFailure() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            let load = Task { await library.load() }
            load.cancel()

            #expect(await load.value == false)
            #expect(library.failure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aNextPageTheScreenLeftIsNoFailure() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            let page = Task { await library.loadMore() }
            page.cancel()
            await page.value

            #expect(library.failure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailureOfAReplacedLoadNoLongerApplies() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.fails = true
            PagedLibraryProtocol.held = [0]
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            let load = Task { await library.load() }
            try await Self.waitForPage("0/60")
            library.list = .movies(.releaseYear, .all)
            PagedLibraryProtocol.held = []

            #expect(await load.value == false)
            #expect(library.failure == nil)
            #expect(library.pageFailure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailureOfAReplacedPageNoLongerApplies() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.fails = true
            PagedLibraryProtocol.held = [0]
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            let page = Task { await library.loadMore() }
            try await Self.waitForPage("0/60")
            library.list = .movies(.releaseYear, .all)
            PagedLibraryProtocol.held = []
            await page.value

            #expect(library.failure == nil)
            #expect(library.pageFailure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailureOfAPageThatALoadBegunBeforeItOvertookNoLongerApplies() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            await library.loadMore()
            await library.loadMore()
            PagedLibraryProtocol.pages = []
            PagedLibraryProtocol.held = [0, 120]

            // the load starts first and answers before the failure begins, so only the page fails, sharing the load's generation
            let load = Task { await library.load() }
            try await Self.waitForPage("0/60")
            PagedLibraryProtocol.fails = true
            let page = Task { await library.loadMore() }
            try await Self.waitForPage("120/60")
            PagedLibraryProtocol.held = [120]
            _ = await load.value
            PagedLibraryProtocol.held = []
            await page.value

            // the page began past the items the load left, so the offset tells its failure is stale
            #expect(library.items.count == 60)
            #expect(library.pageFailure == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aGridWithoutAConnectionSendsNothing() async throws {
        try await withPagedConnection { connection in
            await connection.disconnect()
            PagedLibraryProtocol.pages = []
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            let genres = PagedLibrary.Genres(connection: connection, type: .movie)

            #expect(await library.load() == false)
            await library.loadMore()
            await genres.load()

            #expect(PagedLibraryProtocol.pages.isEmpty)
            #expect(library.items.isEmpty)
            #expect(genres.names.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aReturnToAListShowsItsPageAtOnceAndReloadsItInPlace() async throws {
        try await withPagedConnection { connection in
            await PagedLibrary(connection: connection, list: .movies(.title, .all)).loadMore()
            PagedLibraryProtocol.pages = []
            PagedLibraryProtocol.held = [0]

            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            #expect(library.items.count == 60)
            #expect(library.total == 70)

            let load = Task { await library.loadIfNeeded() }
            try await Self.waitForPage("0/60")
            // the items stay on screen while the first page reloads
            #expect(library.items.count == 60)
            PagedLibraryProtocol.held = []
            await load.value
            // a later appearance keeps the pages it has
            await library.loadIfNeeded()

            #expect(PagedLibraryProtocol.pages == ["0/60"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFirstAppearanceLoadsOnceAndALaterOneKeepsThePages() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            await library.loadIfNeeded()
            await library.loadIfNeeded()

            #expect(library.items.count == 60)
            #expect(PagedLibraryProtocol.pages == ["0/60"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aNewListShowsItsRememberedPageAndAnUnseenOneEmptiesTheGrid() async throws {
        try await withPagedConnection { connection in
            await PagedLibrary(connection: connection, list: .movies(.title, .all)).load()
            PagedLibraryProtocol.total = 90
            let library = PagedLibrary(connection: connection, list: .movies(.releaseYear, .all))
            await library.load()

            library.list = .movies(.title, .all)
            #expect(library.items.count == 60)
            #expect(library.total == 70)

            library.list = .movies(.communityRating, .all)
            #expect(library.items.isEmpty)
            // the total stays until the first page lands
            #expect(library.total == 70)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aReturnToALibraryShowsItsGenresAtOnce() async throws {
        try await withPagedConnection { connection in
            await PagedLibrary.Genres(connection: connection, type: .movie).load()

            #expect(PagedLibrary.Genres(connection: connection, type: .movie).names == ["Comedy", "Drama"])
            #expect(PagedLibrary.Genres(connection: connection, type: .series).names.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aDisconnectForgetsTheRememberedPagesAndGenres() async throws {
        try await withPagedConnection { connection in
            await PagedLibrary(connection: connection, list: .movies(.title, .all)).load()
            await PagedLibrary.Genres(connection: connection, type: .movie).load()

            await connection.disconnect()

            #expect(PagedLibrary(connection: connection, list: .movies(.title, .all)).items.isEmpty)
            #expect(PagedLibrary.Genres(connection: connection, type: .movie).names.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aPageFromBeforeADisconnectIsNotRemembered() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.held = [0]

            let load = Task { await library.load() }
            try await Self.waitForPage("0/60")
            // the session's end report goes out through the same held protocol, so the page goes free once the connection forgot the session
            let disconnect = Task { await connection.disconnect() }
            while connection.isConnected { await Task.yield() }
            PagedLibraryProtocol.held = []
            await disconnect.value
            _ = await load.value

            #expect(connection.firstPages.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRetainedGridDropsAPageFromBeforeADisconnect() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.held = [0]

            let load = Task { await library.load() }
            try await Self.waitForPage("0/60")
            let disconnect = Task { await connection.disconnect() }
            while connection.isConnected { await Task.yield() }
            PagedLibraryProtocol.held = []
            await disconnect.value
            _ = await load.value

            #expect(library.items.isEmpty)
            #expect(library.total == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFirstPageLoadMoreBroughtFromBeforeADisconnectIsDropped() async throws {
        try await withPagedConnection { connection in
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.held = [0]

            let page = Task { await library.loadMore() }
            try await Self.waitForPage("0/60")
            let disconnect = Task { await connection.disconnect() }
            while connection.isConnected { await Task.yield() }
            PagedLibraryProtocol.held = []
            await disconnect.value
            await page.value

            #expect(library.items.isEmpty)
            #expect(connection.firstPages.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func genresFromBeforeADisconnectAreNotRemembered() async throws {
        try await withPagedConnection { connection in
            let genres = PagedLibrary.Genres(connection: connection, type: .movie)
            PagedLibraryProtocol.held = [-1]

            let load = Task { await genres.load() }
            try await Self.waitForPage("genres")
            await connection.disconnect()
            PagedLibraryProtocol.held = []
            await load.value

            #expect(connection.genres.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aLaterPageLeavesTheRememberedFirstPageAlone() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))

            await library.loadMore()
            await library.loadMore()

            #expect(library.items.count == 120)
            #expect(connection.firstPages[.movies(.title, .all)]?.items.first?.id == "item-0")
            #expect(connection.firstPages[.movies(.title, .all)]?.items.count == 60)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aReturnKeepsTheRememberedGenresWhileTheyLoadAgain() async throws {
        try await withPagedConnection { connection in
            connection.genres[.movie] = ["Western"]
            let genres = PagedLibrary.Genres(connection: connection, type: .movie)
            PagedLibraryProtocol.held = [-1]

            let load = Task { await genres.load() }
            try await Self.waitForPage("genres")
            #expect(genres.names == ["Western"])
            PagedLibraryProtocol.held = []
            await load.value

            #expect(genres.names == ["Comedy", "Drama"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRetriedReloadIsNotRepeatedOverPagesAppendedSince() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            await PagedLibrary(connection: connection, list: .movies(.title, .all)).loadMore()
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.fails = true
            await library.loadIfNeeded()
            #expect(library.pageFailure?.isFirstPage == true)
            PagedLibraryProtocol.fails = false

            await library.load()
            await library.loadMore()
            PagedLibraryProtocol.pages = []
            await library.loadIfNeeded()

            #expect(library.items.count == 120)
            #expect(PagedLibraryProtocol.pages.isEmpty)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aPageAppendedDuringACancelledReloadEndsTheRememberedState() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            await PagedLibrary(connection: connection, list: .movies(.title, .all)).loadMore()
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.pages = []
            PagedLibraryProtocol.held = [0]

            let appearance = Task { await library.loadIfNeeded() }
            try await Self.waitForPage("0/60")
            await library.loadMore()
            // leaving the screen cancels the reload, with the appended page on screen
            appearance.cancel()
            PagedLibraryProtocol.held = []
            await appearance.value
            await library.loadIfNeeded()

            #expect(library.items.count == 120)
            #expect(PagedLibraryProtocol.pages == ["0/60", "60/60"])
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRememberedReloadKeepsThePagesAppendedWhileItWasOut() async throws {
        try await withPagedConnection { connection in
            PagedLibraryProtocol.total = 200
            await PagedLibrary(connection: connection, list: .movies(.title, .all)).loadMore()
            let library = PagedLibrary(connection: connection, list: .movies(.title, .all))
            PagedLibraryProtocol.pages = []
            PagedLibraryProtocol.held = [0]

            let appearance = Task { await library.loadIfNeeded() }
            try await Self.waitForPage("0/60")
            await library.loadMore()
            PagedLibraryProtocol.held = []
            await appearance.value

            #expect(library.items.map(\.id) == (0..<120).map { "item-\($0)" })
            await library.loadMore()
            #expect(PagedLibraryProtocol.pages.last == "120/60")
        }
    }

    /// Runs the body with a connection the Keychain restores, whose Jellyfin calls PagedLibraryProtocol answers from a fresh scenario
    private func withPagedConnection(_ body: (JellyfinConnection) async throws -> Void) async throws {
        PagedLibraryProtocol.total = 70
        PagedLibraryProtocol.fails = false
        PagedLibraryProtocol.failStatus = 500
        PagedLibraryProtocol.held = []
        PagedLibraryProtocol.pages = []
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
        stub.protocolClasses = [PagedLibraryProtocol.self]
        let connection = JellyfinConnection(sessionConfiguration: stub, deviceID: { "test" })
        try #require(connection.isConnected)
        try await body(connection)
    }

    /// Waits up to 5 s for the page to reach the stub protocol
    private static func waitForPage(_ page: String) async throws {
        var waited = 0
        while !PagedLibraryProtocol.pages.contains(page), waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        try #require(PagedLibraryProtocol.pages.contains(page))
    }
}
