import Testing
@testable import Biinge

/// Each section's stack keeps the origins of its own screens, so a Back finds the poster its details grew from
struct StackOriginsTests {
    @Test func theSameTitleOpenedInTwoSectionsKeepsEachSectionsOrigin() {
        var origins = StackOrigins<String, String>()
        origins.save("home poster", section: "home", depth: 1)
        origins.save("movies poster", section: "movies", depth: 1)

        #expect(origins.pop(section: "movies", from: 1, to: 0) == "movies poster")
        #expect(origins.pop(section: "home", from: 1, to: 0) == "home poster")
    }

    @Test func aPopReturnsOnlyTheTopScreensOriginAndDropsEveryScreenItRemoved() {
        var origins = StackOrigins<String, String>()
        origins.save("first", section: "home", depth: 1)
        origins.save("third", section: "home", depth: 3)

        // the second screen grew from nothing, so its pop returns nothing though the first screen below has an origin
        #expect(origins.pop(section: "home", from: 2, to: 1) == nil)
        #expect(origins.pop(section: "home", from: 1, to: 0) == "first")
        origins.save("first again", section: "home", depth: 1)
        origins.save("third again", section: "home", depth: 3)

        #expect(origins.pop(section: "home", from: 3, to: 0) == "third again")
        #expect(origins.pop(section: "home", from: 3, to: 0) == nil)
        #expect(origins.pop(section: "home", from: 1, to: 0) == nil)
    }
}
