import Testing
@testable import Biinge

struct SearchResultsTests {
    @Test func aFailedListIsAnErrorNotAnEmptyResult() {
        let results = SearchResults(term: "heat", movies: nil, series: [], games: [], people: [])
        #expect(results.failed)
        #expect(results.isEmpty)
    }

    @Test func fourEmptyListsAreNoResults() {
        let results = SearchResults(term: "zxqv", movies: [], series: [], games: [], people: [])
        #expect(!results.failed)
        #expect(results.isEmpty)
    }

    @Test func aPartialFailureKeepsTheResultsThatLoaded() {
        let movie = SearchMovie(id: 1, title: "Heat", posterPath: "", releaseDate: nil, rating: nil, state: nil)
        let results = SearchResults(term: "heat", movies: [movie], series: nil, games: [], people: [])
        #expect(results.failed)
        #expect(!results.isEmpty)
    }

    @Test func aFreshSearchShowsNoError() {
        #expect(!SearchResults().failed)
    }
}
