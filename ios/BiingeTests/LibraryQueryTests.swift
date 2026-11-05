import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

struct LibraryQueryTests {
    @Test func recentlyAddedMoviesSortsMoviesByDateAddedNewestFirst() throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: .recentlyAddedMovies, userID: "user", startIndex: 0, limit: 20))
        #expect(parameters.includeItemTypes == [.movie])
        #expect(parameters.sortBy == [.dateCreated])
        #expect(parameters.sortOrder == [.descending])
        #expect(parameters.isRecursive == true)
        #expect(parameters.parentID == nil)
        #expect(Set(parameters.fields ?? []).isSuperset(of: [.overview, .genres, .providerIDs]))
    }

    @Test func recentlyAddedSeriesSortsByLastContentAddedNewestFirst() throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: .recentlyAddedSeries, userID: "user", startIndex: 0, limit: 20))
        #expect(parameters.includeItemTypes == [.series])
        #expect(parameters.sortBy == [.dateLastContentAdded])
        #expect(parameters.sortOrder == [.descending])
        #expect(parameters.isRecursive == true)
        #expect(parameters.parentID == nil)
        #expect(Set(parameters.fields ?? []).isSuperset(of: [.overview, .genres, .providerIDs]))
    }

    @Test func collectionListsItsDirectChildrenByYearThenName() throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: .collection("abc"), userID: "user", startIndex: 0, limit: 20))
        #expect(parameters.parentID == "abc")
        #expect(parameters.includeItemTypes == nil)
        #expect(parameters.sortBy == [.productionYear, .sortName])
        #expect(parameters.sortOrder == nil)
        #expect(parameters.isRecursive == nil)
        #expect(Set(parameters.fields ?? []).isSuperset(of: [.overview, .genres, .providerIDs]))
    }

    @Test(arguments: [
        (LibrarySort.recentlyAdded, [ItemSortBy.dateCreated], [JellyfinAPI.SortOrder.descending] as [JellyfinAPI.SortOrder]?),
        (.title, [.sortName], nil),
        (.releaseYear, [.productionYear, .sortName], [.descending, .ascending]),
        (.communityRating, [.communityRating, .sortName], [.descending, .ascending]),
        (.runtime, [.runtime, .sortName], [.descending, .ascending]),
    ])
    func moviesSortInTheChosenOrder(sort: LibrarySort, sortBy: [ItemSortBy], sortOrder: [JellyfinAPI.SortOrder]?) throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: .movies(sort, .all), userID: "user", startIndex: 0, limit: 60))
        #expect(parameters.includeItemTypes == [.movie])
        #expect(parameters.sortBy == sortBy)
        #expect(parameters.sortOrder == sortOrder)
        #expect(parameters.isPlayed == nil)
        #expect(parameters.isRecursive == true)
    }

    @Test(arguments: [
        (LibrarySort.recentlyAdded, [ItemSortBy.dateCreated], [JellyfinAPI.SortOrder.descending] as [JellyfinAPI.SortOrder]?),
        (.title, [.sortName], nil),
        (.releaseYear, [.productionYear, .sortName], [.descending, .ascending]),
        (.communityRating, [.communityRating, .sortName], [.descending, .ascending]),
        // TV shows have no Runtime order and keep the title order
        (.runtime, [.sortName], nil),
    ])
    func seriesSortInTheChosenOrder(sort: LibrarySort, sortBy: [ItemSortBy], sortOrder: [JellyfinAPI.SortOrder]?) throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: .series(sort, .all), userID: "user", startIndex: 0, limit: 60))
        #expect(parameters.includeItemTypes == [.series])
        #expect(parameters.sortBy == sortBy)
        #expect(parameters.sortOrder == sortOrder)
        #expect(parameters.isPlayed == nil)
        #expect(parameters.isRecursive == true)
    }

    @Test(arguments: [(LibraryList.movies(.title, .all), [BaseItemKind.movie]), (.series(.title, .all), [.series])])
    func gridsShowEveryPlayedStateByDefault(list: LibraryList, types: [BaseItemKind]) throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: list, userID: "user", startIndex: 0, limit: 60))
        #expect(parameters.includeItemTypes == types)
        #expect(parameters.isPlayed == nil)
        #expect(parameters.sortBy == [.sortName])
    }

    @Test(arguments: [
        (LibraryList.movies(.title, .unwatched), [BaseItemKind.movie], false),
        (.movies(.title, .watched), [.movie], true),
        (.series(.title, .unwatched), [.series], false),
        (.series(.title, .watched), [.series], true),
    ])
    func gridsNarrowToTheChosenPlayedState(list: LibraryList, types: [BaseItemKind], played: Bool) throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: list, userID: "user", startIndex: 0, limit: 60))
        #expect(parameters.includeItemTypes == types)
        #expect(parameters.isPlayed == played)
        #expect(parameters.sortBy == [.sortName])
    }

    @Test(arguments: [(LibraryList.movies(.title, .all), [BaseItemKind.movie]), (.series(.title, .all), [.series])])
    func gridsShowEveryGenreByDefault(list: LibraryList, types: [BaseItemKind]) throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: list, userID: "user", startIndex: 0, limit: 60))
        #expect(parameters.includeItemTypes == types)
        #expect(parameters.genres == nil)
    }

    @Test(arguments: [
        (LibraryList.movies(.releaseYear, .unwatched, genre: "Science Fiction"), [BaseItemKind.movie]),
        (.series(.releaseYear, .unwatched, genre: "Science Fiction"), [.series]),
    ])
    func gridsNarrowToTheChosenGenre(list: LibraryList, types: [BaseItemKind]) throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: list, userID: "user", startIndex: 0, limit: 60))
        #expect(parameters.includeItemTypes == types)
        #expect(parameters.genres == ["Science Fiction"])
        // the genre narrows the played state and the order rather than replacing them
        #expect(parameters.isPlayed == false)
        #expect(parameters.sortBy == [.productionYear, .sortName])
    }

    @Test func searchPagesTheTermOverTheTypesWithTheCardFields() {
        let parameters = JellyfinAPIService.searchParameters(term: "silo", types: [.movie, .series], userID: "user", startIndex: 20, limit: 20)
        #expect(parameters.searchTerm == "silo")
        #expect(parameters.includeItemTypes == [.movie, .series])
        #expect(parameters.userID == "user")
        #expect(parameters.isRecursive == true)
        #expect(parameters.startIndex == 20)
        #expect(parameters.limit == 20)
        #expect(parameters.fields == [.dateCreated, .childCount])
        #expect(parameters.enableUserData == true)
    }

    @Test func recentlyAddedPagesMoviesAndSeriesTogetherByDateAddedNewestFirst() throws {
        let parameters = try #require(JellyfinAPIService.itemsParameters(for: .recentlyAdded, userID: "user", startIndex: 60, limit: 60))
        #expect(parameters.includeItemTypes == [.movie, .series])
        #expect(parameters.sortBy == [.dateCreated])
        #expect(parameters.sortOrder == [.descending])
        #expect(parameters.startIndex == 60)
        #expect(parameters.limit == 60)
        #expect(parameters.isPlayed == nil)
        #expect(parameters.isRecursive == true)
        #expect(Set(parameters.fields ?? []).isSuperset(of: [.overview, .genres, .providerIDs]))
    }

    @Test func searchMatchesTheTermAcrossTheGivenTypes() {
        let parameters = JellyfinAPIService.searchParameters(term: "alien", types: [.movie, .series], userID: "user", startIndex: 0, limit: 40)
        #expect(parameters.searchTerm == "alien")
        #expect(parameters.includeItemTypes == [.movie, .series])
        #expect(parameters.isRecursive == true)
        #expect(Set(parameters.fields ?? []).isSuperset(of: [.dateCreated, .childCount]))
    }

    @Test(arguments: [LibraryList.continueWatching, .nextUp])
    func listsWithTheirOwnEndpointHaveNoItemsQuery(list: LibraryList) {
        #expect(JellyfinAPIService.itemsParameters(for: list, userID: "user", startIndex: 0, limit: 20) == nil)
    }

    // Copying H.264 and HEVC into fMP4 starts in seconds, and the app draws subtitles from their files
    @Test func transcodingCopiesVideoIntoFMP4WithoutManifestSubtitles() throws {
        let profile = try #require(DeviceProfile.avPlayer.transcodingProfiles?.first)
        #expect(profile.protocol == .hls)
        #expect(profile.container == "mp4")
        #expect(profile.videoCodec == "h264,hevc")
        #expect(profile.enableSubtitlesInManifest == false)
    }

    // Every subtitle is a file the app draws; none is burned in, which would re-encode the video
    @Test func subtitlesAreOnlyExternalFiles() {
        let methods = Set(DeviceProfile.avPlayer.subtitleProfiles?.map(\.method) ?? [])
        #expect(methods == [.external])
    }
}

/// Answers any Jellyfin item list with three items (one without a name) and keeps the URL it was asked
final class JellyfinItemsProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by path if these tests need to run in parallel
    nonisolated(unsafe) static var lastURL: URL?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        Self.lastURL = url
        let body = #"{"Items": [{"Id": "a", "Name": "Drama"}, {"Id": "b"}, {"Id": "c", "Name": "Science Fiction"}], "TotalRecordCount": 3}"#
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The Jellyfin requests the filters and the episode rows send, through a stub protocol
@Suite(.serialized)
struct JellyfinRequestTests {
    private let service: JellyfinAPIService

    init() throws {
        JellyfinItemsProtocol.lastURL = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JellyfinItemsProtocol.self]
        let client = try JellyfinClient(
            configuration: .init(url: #require(URL(string: "https://jellyfin.example.com")), client: "Biinge", deviceName: "Test", deviceID: "test", version: "1"),
            sessionConfiguration: configuration
        )
        service = JellyfinAPIService(client: client, userID: "user")
    }

    /// The query of the last request, by name
    private func lastQuery() throws -> [String: String?] {
        let url = try #require(JellyfinItemsProtocol.lastURL)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
    }

    @Test func genresListTheTypesNamedGenresInNameOrder() async throws {
        let genres = try await service.genres(of: .series)

        // a genre without a name drops out
        #expect(genres == ["Drama", "Science Fiction"])
        #expect(JellyfinItemsProtocol.lastURL?.path == "/Genres")
        let query = try lastQuery()
        #expect(query["userId"] == "user")
        #expect(query["includeItemTypes"] == "Series")
        #expect(query["sortBy"] == "SortName")
        #expect(query["enableImages"] == "false")
    }

    @Test func episodesAskForTheUsersProgressAndOnlyHeldEpisodes() async throws {
        let episodes = try await service.episodes(seriesID: "s", season: 2)

        #expect(episodes.map(\.id) == ["a", "b", "c"])
        #expect(JellyfinItemsProtocol.lastURL?.path == "/Shows/s/Episodes")
        let query = try lastQuery()
        #expect(query["userId"] == "user")
        #expect(query["season"] == "2")
        #expect(query["isMissing"] == "false")
        #expect(query["enableUserData"] == "true")
    }
}
