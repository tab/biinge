import Testing
@testable import Biinge

struct RecentSearchesTests {
    @Test func theNewestTermComesFirst() {
        var recents = RecentSearches()
        recents.add("alien")
        recents.add("dune")
        #expect(recents.terms == ["dune", "alien"])
    }

    @Test func aRepeatedTermMovesToTheFrontOnceWhateverItsCase() {
        var recents = RecentSearches(terms: ["dune", "alien", "heat"])
        recents.add("  Alien ")
        #expect(recents.terms == ["Alien", "dune", "heat"])
    }

    @Test func theListKeepsTheNewestEight() {
        var recents = RecentSearches()
        for index in 1...10 { recents.add("term \(index)") }
        #expect(recents.terms.count == RecentSearches.limit)
        #expect(recents.terms.first == "term 10")
        #expect(recents.terms.last == "term 3")
    }

    @Test func aBlankTermChangesNothing() {
        var recents = RecentSearches(terms: ["dune"])
        recents.add("   ")
        #expect(recents.terms == ["dune"])
    }

    @Test func clearEmptiesTheList() {
        var recents = RecentSearches(terms: ["dune", "alien"])
        recents.clear()
        #expect(recents.terms.isEmpty)
    }

    @Test func theStoredValueRoundTrips() {
        let recents = RecentSearches(terms: ["dune", "Blade \"Runner\""])
        #expect(RecentSearches(rawValue: recents.rawValue) == recents)
        #expect(RecentSearches(rawValue: "not json")?.terms == [])
    }
}
