import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

struct HomeHeroTests {
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    /// A movie with a TMDB ID, so the featured row can open it
    private func movie(_ id: String, added: Date? = nil) -> BaseItemDto {
        BaseItemDto(dateCreated: added, id: id, providerIDs: ["Tmdb": "1"], type: .movie)
    }

    /// A series with a TMDB ID, so the featured row can open it
    private func seriesItem(_ id: String, added: Date? = nil) -> BaseItemDto {
        BaseItemDto(dateCreated: added, id: id, providerIDs: ["Tmdb": "2"], type: .series)
    }

    @Test func continueWatchingWinsOverNewerRecentItems() throws {
        let hero = try #require(HomeHero.featured(
            continueWatching: [movie("resume", added: older), movie("second")],
            recentlyAdded: [movie("movie", added: newer), seriesItem("show", added: newer)]
        ).first)
        #expect(hero.item.id == "resume")
        #expect(hero.isResume)
    }

    @Test(arguments: [("movie", 2_000.0, 1_000.0), ("show", 1_000.0, 2_000.0)])
    func otherwiseTheNewerRecentItemWins(winner: String, movieAdded: Double, seriesAdded: Double) throws {
        let hero = try #require(HomeHero.featured(
            continueWatching: [],
            recentlyAdded: [
                movie("movie", added: Date(timeIntervalSince1970: movieAdded)),
                movie("older movie"),
                seriesItem("show", added: Date(timeIntervalSince1970: seriesAdded)),
            ]
        ).first)
        #expect(hero.item.id == winner)
        #expect(!hero.isResume)
    }

    @Test func aRecentItemWithoutADateLoses() {
        let featured = HomeHero.featured(continueWatching: [], recentlyAdded: [movie("movie"), seriesItem("show", added: older)])
        #expect(featured.map(\.item.id) == ["show", "movie"])
    }

    @Test func aSingleRecentItemSuppliesTheHero() throws {
        let hero = try #require(HomeHero.featured(continueWatching: [], recentlyAdded: [seriesItem("show")]).first)
        #expect(hero.item.id == "show")
    }

    @Test func everyListEmptyHasNoHero() {
        #expect(HomeHero.featured(continueWatching: [], recentlyAdded: []).isEmpty)
    }

    @Test func theRowHoldsContinueWatchingThenRecentItemsNewestFirst() {
        let featured = HomeHero.featured(
            continueWatching: [movie("resume 1"), movie("resume 2")],
            recentlyAdded: [movie("old", added: older), seriesItem("new", added: newer)]
        )
        #expect(featured.map(\.item.id) == ["resume 1", "resume 2", "new", "old"])
        #expect(featured.map(\.isResume) == [true, true, false, false])
    }

    @Test func theRowHoldsFiveTitlesAtMost() {
        let featured = HomeHero.featured(
            continueWatching: (1...3).map { movie("resume \($0)") },
            recentlyAdded: (1...4).map { movie("recent \($0)", added: Date(timeIntervalSince1970: Double(10 - $0))) }
        )
        #expect(featured.map(\.item.id) == ["resume 1", "resume 2", "resume 3", "recent 1", "recent 2"])
    }

    @Test func eachTitleFeaturesOnce() {
        let featured = HomeHero.featured(
            continueWatching: [
                BaseItemDto(id: "e1", seriesID: "s", type: .episode),
                // a second resumed episode of the same series
                BaseItemDto(id: "e2", seriesID: "s", type: .episode),
                movie("m"),
            ],
            recentlyAdded: [seriesItem("s", added: newer), movie("m", added: older), seriesItem("t", added: older)]
        )
        #expect(featured.map(\.item.id) == ["e1", "m", "t"])
    }

    @Test func anItemWithoutAnIDOrASeriesIsNotFeatured() {
        let featured = HomeHero.featured(
            continueWatching: [BaseItemDto(providerIDs: ["Tmdb": "1"], type: .movie), BaseItemDto(id: "e", type: .episode)],
            recentlyAdded: [seriesItem("show")]
        )
        #expect(featured.map(\.item.id) == ["show"])
    }

    // its page would have no working Play or Details, so on Apple TV it would trap the paging
    @Test func aMovieOrSeriesWithoutATMDBIDIsNotFeatured() {
        let featured = HomeHero.featured(
            continueWatching: [BaseItemDto(id: "bare movie", type: .movie), BaseItemDto(id: "e1", seriesID: "bare show", type: .episode)],
            recentlyAdded: [BaseItemDto(id: "bare show", type: .series), BaseItemDto(id: "untyped"), movie("movie")]
        )
        #expect(featured.map(\.item.id) == ["e1", "movie"])
    }

    /// Continue Watching as Jellyfin reports it right after biinge marks movie "marked" and episode "e1" watched (unplayed, with resume positions)
    private let staleContinueWatching = [
        BaseItemDto(id: "marked", providerIDs: ["Tmdb": "1"], type: .movie, userData: UserItemDataDto(isPlayed: false, key: "k", playbackPositionTicks: 600_000_000)),
        BaseItemDto(id: "e1", seriesID: "s", type: .episode, userData: UserItemDataDto(isPlayed: false, key: "k", playbackPositionTicks: 300_000_000)),
        BaseItemDto(id: "other", providerIDs: ["Tmdb": "3"], type: .movie, userData: UserItemDataDto(isPlayed: false, key: "k", playbackPositionTicks: 900_000_000)),
    ]

    /// Next Up as Jellyfin reports it right after the same marks
    private let staleNextUp = [
        BaseItemDto(id: "e1", seriesID: "s", type: .episode),
        BaseItemDto(id: "n1", seriesID: "t", type: .episode),
    ]

    @Test func aWatchedMarkHidesTheItemsThatJellyfinStillReportsUnplayed() throws {
        var continueWatching = staleContinueWatching
        var nextUp = staleNextUp
        var heroNextUps = ["s": BaseItemDto(id: "e1", seriesID: "s", type: .episode), "t": BaseItemDto(id: "n1", seriesID: "t", type: .episode)]

        HomeHero.hideWatched(["marked", "e1"], continueWatching: &continueWatching, nextUp: &nextUp, heroNextUps: &heroNextUps)

        #expect(continueWatching.map(\.id) == ["other"])
        #expect(nextUp.map(\.id) == ["n1"])
        #expect(heroNextUps.keys.sorted() == ["t"])
        let hero = try #require(HomeHero.featured(continueWatching: continueWatching, recentlyAdded: []).first)
        #expect(hero.item.id == "other")
    }

    @Test func aMarkDuringALoadAndALateReloadOfTheStaleListStayFiltered() {
        var watchedIDs: Set<String> = []
        var continueWatching = staleContinueWatching
        var nextUp = staleNextUp
        var heroNextUps: [String: BaseItemDto] = [:]
        // the load's first pass runs before the mark
        HomeHero.hideWatched(watchedIDs, continueWatching: &continueWatching, nextUp: &nextUp, heroNextUps: &heroNextUps)
        #expect(continueWatching.count == 3)

        // the mark lands while the load awaits its hero, and the pass after the last await reads it
        watchedIDs.insert("marked")
        heroNextUps["t"] = BaseItemDto(id: "n1", seriesID: "t", type: .episode)
        HomeHero.hideWatched(watchedIDs, continueWatching: &continueWatching, nextUp: &nextUp, heroNextUps: &heroNextUps)
        #expect(continueWatching.map(\.id) == ["e1", "other"])
        #expect(heroNextUps["t"]?.id == "n1")

        // a reload that started before the mark returns the same stale list after it
        var late = staleContinueWatching
        var lateNextUp = staleNextUp
        var lateHeroNextUps: [String: BaseItemDto] = [:]
        HomeHero.hideWatched(watchedIDs, continueWatching: &late, nextUp: &lateNextUp, heroNextUps: &lateHeroNextUps)
        #expect(late.map(\.id) == ["e1", "other"])
    }

    @Test func anItemWithoutAnIDIsNeverHidden() {
        var continueWatching = [BaseItemDto(type: .movie)]
        var nextUp: [BaseItemDto] = []
        var heroNextUps = ["s": BaseItemDto(type: .episode)]

        HomeHero.hideWatched(["marked"], continueWatching: &continueWatching, nextUp: &nextUp, heroNextUps: &heroNextUps)

        #expect(continueWatching.count == 1)
        #expect(heroNextUps.count == 1)
    }
}
