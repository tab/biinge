import Foundation
import Testing
@testable import Biinge

/// Answers series 20 with season 1 (episodes aired in 2020, then one without an air date) and the progress the running test sets, or the details with a server error while it sets fails; series 21 to 28 are on the server with fixed scenarios (21 lacks its season there, 22 lacks only its next episode, 23 is caught up until an episode in 2999, 24 and 27 have aired episodes to watch, 25 has an episode still to air in each season, 26 is caught up until season 2, and 28 holds only a special still to air, while 27 lists a season 2 the pick never loads); Jellyfin's item and season calls answer from jellyfin.example.com
final class SeriesDetailsStateProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var fails = false
    /// The episode IDs series 20's progress holds as watched
    nonisolated(unsafe) static var watched: [Int] = []
    /// Every season read of series 20, as its path, in order
    nonisolated(unsafe) static var seasonReads: [String] = []
    /// Set while series 20's progress read fails, so the store holds no progress for it
    nonisolated(unsafe) static var progressFails = false
    /// Set while series 20's season reports its aired episodes as watched
    nonisolated(unsafe) static var episodesWatched = false
    /// Set while every episode and season mark answers a server error
    nonisolated(unsafe) static var marksFail = false
    /// Every episode and season mark as "METHOD path", in order (behind a lock, as the URLProtocol thread appends while a test reads)
    static var marks: [String] {
        get { lock.withLock { recorded } }
        set { lock.withLock { recorded = newValue } }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [String] = []
    /// Each mark waits for this semaphore before it answers, so a test can act while the request is in flight
    nonisolated(unsafe) static var markHold: DispatchSemaphore?
    /// The status Jellyfin's item and season calls answer
    nonisolated(unsafe) static var jellyfinStatus = 200

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.host() == "jellyfin.example.com" {
            answer(url, status: Self.jellyfinStatus, body: Self.jellyfinBody(path: url.path))
            return
        }
        let parts = url.pathComponents
        // "/", "api", "v1", "series", id, then "season" and its number or "progress"
        let id = parts.count > 4 && parts[3] == "series" ? Int(parts[4]) ?? 0 : 0
        let tail = parts.count > 5 ? parts[5...].joined(separator: "/") : ""
        let episode = #""posterPath": "", "runtime": 50, "overview": """#
        var status = 200
        let body: String
        switch (id, tail) {
        case (20, ""):
            status = Self.fails ? 500 : 200
            body = Self.fails ? #"{"error": "internal error"}"# : Self.details(id: 20, jellyfinID: nil)
        case (21...24, ""):
            body = Self.details(id: id, jellyfinID: "s\(id)")
        case (25, ""), (26, ""):
            // listed out of order, as the API's seasons need not be sorted
            body = Self.details(id: id, jellyfinID: "s\(id)", seasons: [2, 1])
        case (27, ""):
            body = Self.details(id: id, jellyfinID: "s\(id)", seasons: [1, 2])
        case (28, ""):
            body = Self.details(id: id, jellyfinID: "s\(id)", seasons: [0])
        case (20, "season/1"):
            Self.seasonReads.append(url.path)
            let watched = Self.episodesWatched ? #", "watched": true"# : ""
            body = Self.season([
                #"{"id": 101, "title": "One", "number": 1, \#(episode), "airDate": "2020-01-01"\#(watched)}"#,
                #"{"id": 102, "title": "Two", "number": 2, \#(episode), "airDate": "2020-01-08"\#(watched)}"#,
                #"{"id": 103, "title": "Three", "number": 3, \#(episode)}"#,
            ])
        case (25, "season/1"):
            body = Self.season([
                #"{"id": 251, "title": "One", "number": 1, \#(episode), "airDate": "2020-01-01"}"#,
                #"{"id": 252, "title": "Two", "number": 2, \#(episode), "airDate": "2999-01-01"}"#,
            ])
        case (25, "season/2"):
            body = Self.season([#"{"id": 253, "title": "Three", "number": 1, \#(episode), "airDate": "2999-01-01"}"#])
        case (21...27, "season/1"):
            // 21 has no Jellyfin items, 22 lacks episode 2's, and 23's episode 2 airs in 2999
            let first = id == 21 ? "" : #", "jellyfinId": "e\#(id)1""#
            let second = id == 23 ? #""airDate": "2999-01-01", "jellyfinId": "e232""# : #""airDate": "2020-01-08""#
            body = Self.season([
                #"{"id": \#(id)1, "title": "One", "number": 1, \#(episode), "airDate": "2020-01-01"\#(first)}"#,
                #"{"id": \#(id)2, "title": "Two", "number": 2, \#(episode), \#(second)}"#,
            ])
        case (26, "season/2"):
            body = Self.season([#"{"id": 263, "title": "Three", "number": 1, \#(episode), "airDate": "2999-01-01"}"#])
        case (28, "season/0"):
            body = Self.season([#"{"id": 281, "title": "Special", "number": 1, \#(episode), "airDate": "2999-01-01"}"#])
        case (20, "progress") where Self.progressFails:
            status = 500
            body = #"{"error": "internal error"}"#
        case (_, "progress"):
            let watched = switch id {
            case 20: Self.watched
            case 24, 27, 28: [Int]()
            case 26: [261, 262]
            default: [id * 10 + 1]
            }
            body = Self.progress(id: id, watched: watched)
        case (_, let tail) where tail.hasPrefix("seasons/"):
            Self.lock.withLock { Self.recorded.append("\(request.httpMethod ?? "") \(url.path)") }
            // the timeout keeps a failed test from blocking the session's thread for good
            _ = Self.markHold?.wait(timeout: .now() + 5)
            status = Self.marksFail ? 500 : 200
            body = Self.marksFail ? #"{"error": "internal error"}"# : Self.progress(id: id, watched: Self.watched)
        default:
            body = #"{"data": [], "meta": {"page": 1, "per": 10000, "total": 0}}"#
        }
        answer(url, status: status, body: body)
    }

    override func stopLoading() {}

    private func answer(_ url: URL, status: Int, body: String) {
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Jellyfin's answer: one episode with a resume position for a season's episodes, or the item the path names with a stored position
    private static func jellyfinBody(path: String) -> String {
        guard !path.hasSuffix("/Episodes") else {
            return #"{"Items": [{"Id": "e241", "UserData": {"Key": "e241", "PlaybackPositionTicks": 10, "PlayedPercentage": 40}}], "TotalRecordCount": 1}"#
        }
        return #"{"Id": "\#(path.split(separator: "/").last ?? "")", "UserData": {"Key": "item", "PlaybackPositionTicks": 42}}"#
    }

    private static func progress(id: Int, watched: [Int]) -> String {
        #"{"id": \#(id), "state": "watching", "trackedState": "watching", "watchedSeasons": [], "watchedEpisodes": \#(watched)}"#
    }

    /// The series' details with these seasons, on the server under `jellyfinID` (nil for not on it)
    private static func details(id: Int, jellyfinID: String?, seasons: [Int] = [1]) -> String {
        let item = jellyfinID.map { #", "jellyfinId": "\#($0)""# } ?? ""
        let listed = seasons.map { #"{"id": \#(199 + $0), "title": "Season \#($0)", "number": \#($0), "posterPath": "", "episodesCount": 3}"# }
        return #"{"id": \#(id), "title": "Silo", "posterPath": "", "pinned": false, "state": "watching", "overview": "", "status": "Returning Series", "#
            + #""genres": [], "credits": [], "recommendations": [], "videos": [], "seasons": [\#(listed.joined(separator: ", "))]\#(item)}"#
    }

    /// Season 1 holding these episodes
    private static func season(_ episodes: [String]) -> String {
        #"{"id": 200, "title": "Season 1", "number": 1, "posterPath": "", "overview": "", "episodes": [\#(episodes.joined(separator: ", "))]}"#
    }
}

@MainActor
@Suite(.serialized)
struct SeriesDetailsStateTests {
    private let model: SeriesDetailsState
    private let apiClient: Biinge.APIClient
    private let store: SeriesStore
    private let connection: JellyfinConnection

    init() {
        SeriesDetailsStateProtocol.fails = false
        SeriesDetailsStateProtocol.watched = []
        SeriesDetailsStateProtocol.seasonReads = []
        SeriesDetailsStateProtocol.progressFails = false
        SeriesDetailsStateProtocol.episodesWatched = false
        SeriesDetailsStateProtocol.marksFail = false
        SeriesDetailsStateProtocol.marks = []
        SeriesDetailsStateProtocol.markHold = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SeriesDetailsStateProtocol.self]
        apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
        store = SeriesStore(apiClient: apiClient)
        connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        model = SeriesDetailsState(apiClient: apiClient, store: store, connection: connection, seriesID: 20)
    }

    /// A model of the series on this suite's store and connection
    private func series(_ id: Int) -> SeriesDetailsState {
        SeriesDetailsState(apiClient: apiClient, store: store, connection: connection, seriesID: id)
    }

    @Test func theNextEpisodeIsTheFirstAiredOneBiingeHasntMarked() async {
        SeriesDetailsStateProtocol.watched = [101]

        await model.load()

        #expect(model.season == 1)
        #expect(model.nextEpisode?.id == 102)
        #expect(!model.isCaughtUp)
        // no Jellyfin item has loaded for the episode
        #expect(model.nextPosition == 0)
    }

    @Test func anEpisodeWithoutAnAirDateCountsAsUpcoming() async {
        SeriesDetailsStateProtocol.watched = [101, 102]

        await model.load()

        // caught up, the pick offers the opener again
        #expect(model.nextEpisode?.id == 101)
        #expect(model.isCaughtUp)
        #expect(model.upcoming?.season == 1)
        #expect(model.upcoming?.episode.id == 103)
    }

    @Test func everyLoadStartsTheSeasonsOver() async {
        await model.load()
        let first = model.seasons

        // a new Jellyfin connection loads again, so episodes cached before it lose their stale Jellyfin items
        await model.load()

        #expect(model.seasons !== first)
        #expect(model.seasons.episodes[1]?.count == 3)
        #expect(SeriesDetailsStateProtocol.seasonReads.count == 2)
    }

    @Test func aFailedFirstLoadKeepsItsErrorUntilARetryLands() async {
        SeriesDetailsStateProtocol.fails = true
        await model.load()

        #expect(model.details == nil)
        #expect(model.failure != nil)

        SeriesDetailsStateProtocol.fails = false
        await model.load()

        #expect(model.details?.title == "Silo")
        #expect(model.failure == nil)
    }

    @Test func aFailedReloadKeepsTheDetailsOnScreen() async {
        await model.load()
        SeriesDetailsStateProtocol.fails = true

        await model.load()

        #expect(model.details?.title == "Silo")
        #expect(model.failure == nil)
    }

    @Test func aSeriesOffTheServerHasNoEpisodeNote() async {
        SeriesDetailsStateProtocol.watched = [101]

        await model.load()

        // the next episode has no Jellyfin item, but neither has the series
        #expect(model.nextEpisode?.id == 102)
        #expect(model.episodeNote == nil)
    }

    @Test func nothingIsOfferedBeforeTheFirstLoad() {
        #expect(model.next.season == nil)
        #expect(model.nextEpisode == nil)
        #expect(!model.isCaughtUp)
        #expect(model.upcoming == nil)
    }

    @Test func withoutProgressTheEpisodesOwnMarksSayWhetherTheUserIsCaughtUp() async {
        SeriesDetailsStateProtocol.progressFails = true
        SeriesDetailsStateProtocol.episodesWatched = true

        await model.load()

        #expect(model.progress == nil)
        // caught up, the pick offers the opener again
        #expect(model.nextEpisode?.id == 101)
        #expect(model.isCaughtUp)
    }

    @Test func theUpcomingEpisodeCanSitInALaterSeasonThatLoadsBesideTheShownOne() async {
        let model = series(26)

        await model.load()

        #expect(model.season == 1)
        #expect(model.seasons.episodes[2]?.count == 1)
        #expect(model.isCaughtUp)
        #expect(model.upcoming?.season == 2)
        #expect(model.upcoming?.episode.id == 263)
    }

    @Test func theUpcomingEpisodeIsTheEarliestSeasonsWhateverOrderTheAPIListsThem() async {
        let model = series(25)
        await model.load()

        await model.seasons.load(2)

        #expect(model.upcoming?.season == 1)
        #expect(model.upcoming?.episode.id == 252)
    }

    @Test func aSeriesWithEveryLoadedEpisodeAiredHasNoUpcomingEpisode() async {
        let model = series(27)

        await model.load()

        #expect(model.nextEpisode?.id == 271)
        // the pick never needed season 2, so it has no episodes to read
        #expect(model.seasons.episodes[2] == nil)
        #expect(model.upcoming == nil)
    }

    @Test func aSeriesOfOnlySpecialsShowsItsFirstSeasonAndOffersNothing() async {
        let model = series(28)

        await model.load()

        #expect(model.season == 0)
        #expect(model.seasons.episodes[0]?.count == 1)
        #expect(model.nextEpisode == nil)
        // a special still to air never counts as upcoming
        #expect(model.upcoming == nil)
    }

    @Test func aWatchedMarkLandsThroughTheStoreAndMirrorsToJellyfin() async throws {
        let model = series(23)
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        let second = try #require(episodes.last)
        SeriesDetailsStateProtocol.watched = [231, 232]

        #expect(await model.setWatched(true, episode: second, season: season, seasonEpisodes: episodes))

        #expect(SeriesDetailsStateProtocol.marks == ["POST /api/v1/series/23/seasons/200/episodes/232/watched"])
        #expect(model.progress?.watchedEpisodes.contains(232) == true)
        #expect(connection.watchedIDs.contains("e232"))
        #expect(model.watchedFailure == nil)
    }

    @Test func aWatchedMarkReachesTheMirrorBeforeItsWriteEnds() async throws {
        let model = series(23)
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        let second = try #require(episodes.last)
        let hold = DispatchSemaphore(value: 0)
        SeriesDetailsStateProtocol.markHold = hold

        let mark = Task { await model.setWatched(true, episode: second, season: season, seasonEpisodes: episodes) }
        var waited = 0
        while SeriesDetailsStateProtocol.marks.isEmpty, waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }

        #expect(SeriesDetailsStateProtocol.marks.count == 1)
        #expect(connection.watchedIDs.contains("e232"))
        hold.signal()
        _ = await mark.value
    }

    @Test func aWatchedUnmarkTakesTheMirrorBack() async throws {
        let model = series(23)
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        let first = try #require(episodes.first)
        connection.setWatched(itemID: "e231", watched: true)

        await model.setWatched(false, episode: first, season: season, seasonEpisodes: episodes)

        #expect(SeriesDetailsStateProtocol.marks == ["DELETE /api/v1/series/23/seasons/200/episodes/231/watched"])
        #expect(!connection.watchedIDs.contains("e231"))
    }

    @Test func aFailedWatchedMarkSaysSoAndFollowsTheProgressTheStoreRestored() async throws {
        let model = series(23)
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        let second = try #require(episodes.last)
        SeriesDetailsStateProtocol.marksFail = true

        #expect(await model.setWatched(true, episode: second, season: season, seasonEpisodes: episodes) == false)

        #expect(model.watchedFailure?.hasPrefix("Nothing changed. ") == true)
        #expect(model.progress?.watchedEpisodes == [231])
        #expect(!connection.watchedIDs.contains("e232"))
    }

    @Test func aSeasonMarkReturnsWhetherItLanded() async throws {
        let model = series(23)
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        SeriesDetailsStateProtocol.watched = [231, 232]

        #expect(await model.markSeason(season, episodes: episodes, watched: true))
        #expect(SeriesDetailsStateProtocol.marks == ["POST /api/v1/series/23/seasons/200/watched"])
        #expect(model.progress?.watchedEpisodes == [231, 232])
        #expect(model.watchedFailure == nil)

        SeriesDetailsStateProtocol.marksFail = true
        #expect(await model.markSeason(season, episodes: episodes, watched: false) == false)
        #expect(model.watchedFailure?.hasPrefix("Nothing changed. ") == true)
    }

    @Test func aSeasonMarkReachesTheMirrorBeforeItsWriteEnds() async throws {
        let model = series(23)
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        SeriesDetailsStateProtocol.watched = [231, 232]
        let hold = DispatchSemaphore(value: 0)
        SeriesDetailsStateProtocol.markHold = hold

        let mark = Task { await model.markSeason(season, episodes: episodes, watched: true) }
        var waited = 0
        while SeriesDetailsStateProtocol.marks.isEmpty, waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }

        #expect(connection.watchedIDs == ["e231", "e232"])
        hold.signal()
        #expect(await mark.value)
        #expect(connection.watchedIDs == ["e231", "e232"])
    }

    @Test func aSeasonUnmarkTakesTheMirrorBack() async throws {
        let model = series(23)
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        connection.setWatched(itemID: "e231", watched: true)
        connection.setWatched(itemID: "e232", watched: true)
        let hold = DispatchSemaphore(value: 0)
        SeriesDetailsStateProtocol.markHold = hold

        let unmark = Task { await model.markSeason(season, episodes: episodes, watched: false) }
        var waited = 0
        while SeriesDetailsStateProtocol.marks.isEmpty, waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }

        // the mirror moves before the write ends
        #expect(connection.watchedIDs.isEmpty)
        hold.signal()
        #expect(await unmark.value)

        #expect(SeriesDetailsStateProtocol.marks == ["DELETE /api/v1/series/23/seasons/200/watched"])
        #expect(connection.watchedIDs.isEmpty)
    }

    @Test func aFailedMarkWithNoEarlierProgressLeavesNone() async throws {
        SeriesDetailsStateProtocol.progressFails = true
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        let first = try #require(episodes.first)
        SeriesDetailsStateProtocol.marksFail = true

        #expect(await model.setWatched(true, episode: first, season: season, seasonEpisodes: episodes) == false)
        #expect(model.progress == nil)

        #expect(await model.markSeason(season, episodes: episodes, watched: true) == false)
        #expect(model.progress == nil)
    }

    @Test func aFailedSeasonMarkFollowsTheProgressTheStoreRestored() async throws {
        let model = series(23)
        await model.load()
        let (season, episodes) = try seasonOne(of: model)
        SeriesDetailsStateProtocol.marksFail = true

        #expect(await model.markSeason(season, episodes: episodes, watched: true) == false)

        #expect(model.progress?.watchedEpisodes == [231])
        // only the episode the server still holds as watched stays hidden
        #expect(connection.watchedIDs == ["e231"])
    }

    @Test func marksWaitForTheDetails() async throws {
        let loaded = series(23)
        await loaded.load()
        let (season, episodes) = try seasonOne(of: loaded)
        let first = try #require(episodes.first)
        let model = series(23)

        await model.setWatched(true, episode: first, season: season, seasonEpisodes: episodes)

        #expect(await model.markSeason(season, episodes: episodes, watched: true) == false)
        #expect(SeriesDetailsStateProtocol.marks.isEmpty)
        #expect(connection.watchedIDs.isEmpty)
    }

    /// The model's first season and its loaded episodes
    private func seasonOne(of model: SeriesDetailsState) throws -> (SeasonSummary, [EpisodeSummary]) {
        (try #require(model.details?.seasons.first), try #require(model.seasons.episodes[1]))
    }
}

// the episode notes need a connected connection, which comes from the Keychain, so this test shares JellyfinConnectionTests' serialized Keychain runs
extension JellyfinConnectionTests {
    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"), arguments: [
        (21, PlayNote.Kind.seasonNotOnServer, "You’re up to S1 · E2. Season 1 isn’t on Living Room."),
        (22, PlayNote.Kind.notOnServer, "Not on Living Room. Add it to Jellyfin to play here."),
        (23, PlayNote.Kind.airs, "You’re caught up. S1 · E2 airs "),
    ])
    func theEpisodeNoteSaysWhereTheNextEpisodeStands(seriesID: Int, kind: PlayNote.Kind, text: String) async throws {
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
        let stub = URLSessionConfiguration.ephemeral
        stub.protocolClasses = [SeriesDetailsStateProtocol.self]
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: stub)
        let model = SeriesDetailsState(apiClient: apiClient, store: SeriesStore(apiClient: apiClient), connection: connection, seriesID: seriesID)

        await model.load()

        let note = try #require(model.episodeNote)
        #expect(note.kind == kind)
        // the air date's day formats with the device's locale
        #expect(note.text.hasPrefix(text))
    }

    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aNextEpisodeTheServerHoldsHasNoNoteAndPlays() async throws {
        try await withSeriesConnection(seriesID: 24) { model, _, _ in
            await model.load()

            #expect(model.seriesPlay == .play("s24"))
            #expect(model.nextPlay == .play("e241"))
            #expect(model.episodeNote == nil)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func theNextItemGivesItsStoredPositionUntilTheNextEpisodeMoves() async throws {
        try await withSeriesConnection(seriesID: 24) { model, store, _ in
            await model.load()

            await model.loadNextItem()

            #expect(model.nextItem?.id == "e241")
            #expect(model.nextPosition == 42)

            let details = try #require(model.details)
            store.apply(
                WatchProgress(id: 24, state: .watching, trackedState: .watching, watchedSeasons: [], watchedEpisodes: [241]),
                id: 24, title: details.title, posterPath: details.posterPath, episodesCount: details.totalEpisodesCount, pinned: details.pinned
            )

            #expect(model.nextEpisode?.id == 242)
            #expect(model.nextPosition == 0)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func theSeriesItemAndTheSeasonsSharesLoadFromTheServer() async throws {
        try await withSeriesConnection(seriesID: 24) { model, _, _ in
            await model.load()

            await model.loadSeriesItem()
            await model.loadShares()

            #expect(model.seriesItem?.id == "s24")
            let episode = try #require(model.seasons.episodes[1]?.first)
            #expect(model.seasons.share(episode) == 0.4)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aFailedJellyfinLoadKeepsTheConnectionAndLeavesItsItemOut() async throws {
        try await withSeriesConnection(seriesID: 24) { model, _, connection in
            await model.load()
            SeriesDetailsStateProtocol.jellyfinStatus = 500

            await model.loadSeriesItem()
            await model.loadNextItem()
            await model.loadShares()

            #expect(model.seriesItem == nil)
            #expect(model.nextItem == nil)
            #expect(connection.isConnected)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRevokedTokenOnTheSeriesItemDisconnects() async throws {
        try await withSeriesConnection(seriesID: 24) { model, _, connection in
            await model.load()
            SeriesDetailsStateProtocol.jellyfinStatus = 401

            await model.loadSeriesItem()

            #expect(!connection.isConnected)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRevokedTokenOnTheNextItemDisconnects() async throws {
        try await withSeriesConnection(seriesID: 24) { model, _, connection in
            await model.load()
            SeriesDetailsStateProtocol.jellyfinStatus = 401

            await model.loadNextItem()

            #expect(!connection.isConnected)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aRevokedTokenOnTheSharesDisconnects() async throws {
        try await withSeriesConnection(seriesID: 24) { model, _, connection in
            await model.load()
            SeriesDetailsStateProtocol.jellyfinStatus = 401

            await model.loadShares()

            #expect(!connection.isConnected)
        }
    }

    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aDisconnectedSeriesAsksToConnectAndLoadsNothingFromJellyfin() async throws {
        try await withSeriesConnection(seriesID: 24) { model, _, connection in
            await model.load()
            await connection.disconnect()

            await model.loadSeriesItem()
            await model.loadNextItem()
            await model.loadShares()

            #expect(model.nextPlay == .connect)
            #expect(model.seriesItem == nil)
            #expect(model.nextItem == nil)
        }
    }

    /// Runs the body with a model of the series, its store and a connection the Keychain restores, whose API and Jellyfin calls SeriesDetailsStateProtocol answers
    private func withSeriesConnection(seriesID: Int, _ body: (SeriesDetailsState, SeriesStore, JellyfinConnection) async throws -> Void) async throws {
        SeriesDetailsStateProtocol.jellyfinStatus = 200
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
        stub.protocolClasses = [SeriesDetailsStateProtocol.self]
        let connection = JellyfinConnection(sessionConfiguration: stub, deviceID: { "test" })
        try #require(connection.isConnected)
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: stub)
        let store = SeriesStore(apiClient: apiClient)
        try await body(SeriesDetailsState(apiClient: apiClient, store: store, connection: connection, seriesID: seriesID), store, connection)
    }
}
