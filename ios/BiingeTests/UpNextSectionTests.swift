import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

struct UpNextSectionTests {
    private let resume = [BaseItemDto(id: "r1", type: .movie)]
    private let nextUp = [BaseItemDto(id: "n1", type: .episode)]

    private func tracked(_ json: String) throws -> UpNext {
        try JSONDecoder().decode(UpNext.self, from: Data(json.utf8))
    }

    @Test func jellyfinRowsLeadTheTrackedQueue() throws {
        let queue = try tracked(#"{"episodes": [{"seriesId": 1, "id": 2, "seasonNumber": 1, "number": 3}], "movies": [{"id": 4}], "games": [{"id": 5}]}"#)
        let sections = UpNextSection.compose(continueWatching: resume, nextUp: nextUp, tracked: queue)
        #expect(sections.map(\.title) == ["Continue Watching", "Next Episodes", "New Episodes", "Movies", "Games"])
    }

    @Test func withoutJellyfinOnlyTheTrackedQueueShows() throws {
        let queue = try tracked(#"{"movies": [{"id": 4}]}"#)
        let sections = UpNextSection.compose(continueWatching: [], nextUp: [], tracked: queue)
        #expect(sections.map(\.title) == ["Movies"])
        #expect(LoadState(hasLoaded: true, isEmpty: sections.isEmpty, loadError: nil) == nil)
    }

    @Test func jellyfinRowsAloneKeepTheEmptyStateAway() throws {
        let sections = UpNextSection.compose(continueWatching: [], nextUp: nextUp, tracked: try tracked("{}"))
        #expect(sections.map(\.title) == ["Next Episodes"])
        #expect(LoadState(hasLoaded: true, isEmpty: sections.isEmpty, loadError: nil) == nil)
    }

    @Test func theEmptyStateShowsOnlyWhenBothAreEmpty() throws {
        let sections = UpNextSection.compose(continueWatching: [], nextUp: [], tracked: try tracked("{}"))
        #expect(sections.isEmpty)
        #expect(LoadState(hasLoaded: true, isEmpty: sections.isEmpty, loadError: nil) == .empty)
    }

    @Test func aFailedLoadWithNothingToShowShowsItsError() throws {
        struct Failure: LocalizedError {
            var errorDescription: String? { "Offline" }
        }
        let sections = UpNextSection.compose(continueWatching: [], nextUp: [], tracked: try tracked("{}"))
        #expect(LoadState(hasLoaded: true, isEmpty: sections.isEmpty, loadError: Failure()) == .failed("Offline"))
    }
}
