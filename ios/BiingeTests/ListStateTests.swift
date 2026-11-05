import Foundation
import Testing
@testable import Biinge

struct ListStateTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? { "The network connection was lost." }
    }

    private let games = [
        LibraryGame(id: 1, title: "Tunic", posterPath: "", pinned: true, state: .want),
        LibraryGame(id: 2, title: "hades", posterPath: "", pinned: false, state: .want),
        LibraryGame(id: 3, title: "Celeste", posterPath: "", pinned: false, state: .want),
    ]

    @Test func theDateAddedSortKeepsTheStoreOrder() {
        #expect(ListSort.added.sorted(games, title: \.title).map(\.id) == [1, 2, 3])
    }

    @Test func theTitleSortIgnoresCase() {
        #expect(ListSort.title.sorted(games, title: \.title).map(\.title) == ["Celeste", "hades", "Tunic"])
    }

    @Test func theTitleSortKeepsTheStoreOrderForEqualTitles() {
        let remakes = (1...12).map { LibraryGame(id: $0, title: $0.isMultiple(of: 2) ? "Prey" : "Alan Wake", posterPath: "", pinned: false, state: .want) }

        let sorted = ListSort.title.sorted(remakes, title: \.title)

        #expect(sorted.map(\.id) == [1, 3, 5, 7, 9, 11, 2, 4, 6, 8, 10, 12])
    }

    @Test func theSortKeepsTheValuesItStores() {
        #expect(ListSort.title.rawValue == "title")
        #expect(ListSort.added.rawValue == "added")
    }

    @Test func aFailedListLoadShowsTheErrorInsteadOfTheEmptyState() {
        // a failed first load, and a failed refresh of a list that is empty now
        #expect(LoadState(hasLoaded: false, isEmpty: true, loadError: Failure()) == .failed("The network connection was lost."))
        #expect(LoadState(hasLoaded: true, isEmpty: true, loadError: Failure()) == .failed("The network connection was lost."))
    }

    @Test func aListWithTitlesShowsThemThroughAFailedRefresh() {
        #expect(LoadState(hasLoaded: true, isEmpty: false, loadError: Failure()) == nil)
        #expect(LoadState(hasLoaded: true, isEmpty: false, loadError: nil) == nil)
    }

    @Test func anEmptyListIsLoadingUntilItsFirstLoadThenEmpty() {
        #expect(LoadState(hasLoaded: false, isEmpty: true, loadError: nil) == .loading)
        #expect(LoadState(hasLoaded: true, isEmpty: true, loadError: nil) == .empty)
    }

    @Test func theLibraryAsksToConnectWhateverItLoaded() {
        #expect(LoadState(isConnected: false, total: nil, failure: nil) == .notConnected)
        #expect(LoadState(isConnected: false, total: 12, failure: "Offline") == .notConnected)
    }

    @Test func theLibraryIsLoadingUntilItsFirstPageLands() {
        #expect(LoadState(isConnected: true, total: nil, failure: nil) == .loading)
    }

    @Test func aFailedFirstLibraryLoadShowsTheUnreachableState() {
        #expect(LoadState(isConnected: true, total: nil, failure: "Offline") == .failed("Offline"))
    }

    @Test func aLibraryWithNoItemsIsEmpty() {
        #expect(LoadState(isConnected: true, total: 0, failure: nil) == .empty)
    }

    @Test func aFailedReloadOfAnEmptyLibraryShowsTheUnreachableState() {
        #expect(LoadState(isConnected: true, total: 0, failure: "Offline") == .failed("Offline"))
    }

    @Test func aLibraryWithItemsShowsThemThroughALaterFailure() {
        #expect(LoadState(isConnected: true, total: 214, failure: nil) == nil)
        #expect(LoadState(isConnected: true, total: 214, failure: "Offline") == nil)
    }
}
