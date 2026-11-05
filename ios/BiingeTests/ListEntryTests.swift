import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

struct ListEntryTests {
    private let movies = [
        LibraryMovie(id: 1, title: "Zodiac", posterPath: "/z.jpg", pinned: true, state: .want, jellyfinID: "j1"),
        LibraryMovie(id: 2, title: "arrival", posterPath: "/a.jpg", pinned: false, state: .want, jellyfinID: nil),
    ]
    private let series = [
        LibrarySeries(id: 1, title: "Silo", posterPath: "/s.jpg", pinned: false, state: .want, episodesCount: 10, watchedEpisodesCount: 4, jellyfinID: "j2"),
    ]

    @Test func moviesComeBeforeSeriesInTheStoreOrder() {
        let entries = ListEntry.entries(movies: movies, series: series)

        #expect(entries.map(\.title) == [.movie(1), .movie(2), .series(1)])
        #expect(entries[0] == ListEntry(title: .movie(1), name: "Zodiac", posterPath: "/z.jpg", pinned: true, progress: nil, jellyfinID: "j1"))
        #expect(entries[2].jellyfinID == "j2")
        #expect(entries[2].progress == 0.4)
    }

    @Test func theTitleSortIgnoresCase() {
        #expect(ListEntry.entries(movies: movies, series: series, sort: .title).map(\.name) == ["arrival", "Silo", "Zodiac"])
    }

    @Test func theTitleSortOrdersNumbersByValue() {
        let sequels = [
            LibraryMovie(id: 10, title: "Rocky 10", posterPath: "", pinned: false, state: .want, jellyfinID: nil),
            LibraryMovie(id: 2, title: "Rocky 2", posterPath: "", pinned: false, state: .want, jellyfinID: nil),
        ]

        #expect(ListEntry.entries(movies: sequels, series: [], sort: .title).map(\.name) == ["Rocky 2", "Rocky 10"])
    }

    @Test func aMovieAndASeriesWithOneTMDBIDAreDistinctEntries() {
        let ids = ListEntry.entries(movies: movies, series: series).map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test(arguments: ["j1", nil] as [String?])
    func theListItemsDecodeWithAndWithoutAJellyfinID(jellyfinID: String?) throws {
        let id = jellyfinID.map { #", "jellyfinId": "\#($0)""# } ?? ""
        let movie = Data(#"{"id": 1, "title": "Heat", "posterPath": "", "pinned": false, "state": "want"\#(id)}"#.utf8)
        let series = Data(#"{"id": 2, "title": "Silo", "posterPath": "", "pinned": false, "state": "watching", "episodesCount": 10, "watchedEpisodesCount": 4\#(id)}"#.utf8)

        #expect(try JSONDecoder().decode(LibraryMovie.self, from: movie).jellyfinID == jellyfinID)
        #expect(try JSONDecoder().decode(LibrarySeries.self, from: series).jellyfinID == jellyfinID)
    }

    @Test func aTitleWithoutAJellyfinItemIsOffServerOnlyWhileConnected() {
        let entries = ListEntry.entries(movies: movies, series: series)

        // Zodiac and Silo have an item, arrival has none
        #expect(entries.map { $0.isOffServer(connected: true) } == [false, true, false])
        #expect(entries.map { $0.isOffServer(connected: false) } == [false, false, false])
    }

    @Test func resumeSharesKeepOnlyItemsWithAPosition() {
        let items = [
            BaseItemDto(id: "half", userData: UserItemDataDto(key: "k", playbackPositionTicks: 600_000_000, playedPercentage: 50)),
            BaseItemDto(id: "unstarted", userData: UserItemDataDto(key: "k", playbackPositionTicks: 0, playedPercentage: 0)),
            BaseItemDto(id: "noData"),
        ]

        #expect(ListEntry.resumeShares(items) == ["half": 0.5])
    }
}
