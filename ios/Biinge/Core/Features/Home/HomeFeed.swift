import Foundation
import JellyfinAPI
import Observation

/// Home's Jellyfin rows on the Mac and Apple TV: Continue Watching, Next Up, the recently added lists and Collections, with each featured title's Play and Details lookups and the load errors
@MainActor
@Observable
final class HomeFeed {
    /// The rows of one load
    struct Rows {
        var continueWatching: [BaseItemDto]
        var nextUp: [BaseItemDto]
        /// Each recently added list's page, in the order the feed names the lists
        var recentlyAdded: [LibraryPage]
        let collections: [BaseItemDto]
    }

    private let connection: JellyfinConnection
    /// The recently added lists Home shows, each with the most items it loads
    private let recentLists: [(list: LibraryList, limit: Int)]

    /// The rows on screen, nil until the first load lands
    private(set) var rows: Rows?
    /// The first load's error message, nil once rows are on screen
    private(set) var failure: String?
    /// A failed reload's error message, shown over the rows an earlier load brought
    private(set) var reloadFailure: String?
    /// The next up episode of each series hero by its item ID, which its Play plays
    private(set) var heroNextUps: [String: BaseItemDto] = [:]
    /// The series details each episode hero opens by its item ID, missing until its fetch lands or when it fails (a movie or series hero opens its own)
    private(set) var heroTitles: [String: DetailsTitle] = [:]
    /// Bumped by every load, so a load a newer one overtook publishes nothing
    private var generation = 0

    /// A feed of the recently added lists, in the order its rows hold their pages (the Mac's movies and series together, Apple TV's movies then series)
    init(connection: JellyfinConnection, recentlyAdded: [(list: LibraryList, limit: Int)]) {
        self.connection = connection
        recentLists = recentlyAdded
    }

    /// The featured row of the rows on screen (empty until they land)
    var heroes: [HomeHero] {
        guard let rows else { return [] }
        return HomeHero.featured(continueWatching: rows.continueWatching, recentlyAdded: rows.recentlyAdded.flatMap(\.items))
    }

    /// Clears the rows and errors back to the loading state, then loads again (the empty and offline states' action)
    func reload() async {
        rows = nil
        failure = nil
        reloadFailure = nil
        await load()
    }

    /// Hides the titles biinge just marked watched from the rows on screen at once, then loads again, which resolves the details of a hero the marks promoted
    func hideWatched() async {
        guard var shown = rows else { return }
        HomeHero.hideWatched(connection.watchedIDs, continueWatching: &shown.continueWatching, nextUp: &shown.nextUp, heroNextUps: &heroNextUps)
        rows = shown
        await load()
    }

    /// Loads every row in parallel, then each hero's Play and Details as its lookup lands; a revoked token disconnects, a failed first load shows the offline state and a failed reload the error line
    func load() async {
        guard let service = connection.service else { return }
        generation += 1
        let started = generation
        let recentLists = recentLists
        do {
            async let continueWatching = service.page(of: .continueWatching, startIndex: 0, limit: 20)
            async let nextUp = service.page(of: .nextUp, startIndex: 0, limit: 20)
            async let recentlyAdded = withThrowingTaskGroup(of: (index: Int, page: LibraryPage).self) { group in
                for (index, recent) in recentLists.enumerated() {
                    group.addTask { (index, try await service.page(of: recent.list, startIndex: 0, limit: recent.limit)) }
                }
                var pages: [Int: LibraryPage] = [:]
                for try await loaded in group { pages[loaded.index] = loaded.page }
                return recentLists.indices.compactMap { pages[$0] }
            }
            async let collections = service.page(of: .collections, startIndex: 0, limit: 20)
            var loaded = try await Rows(
                continueWatching: continueWatching.items,
                nextUp: nextUp.items,
                recentlyAdded: recentlyAdded,
                collections: collections.items
            )
            // a newer load started during the awaits, and its rows win
            guard started == generation else { return }
            // Jellyfin may still report a title biinge just marked watched, so the marks as they stand after the last await filter every load, a stale or late one too
            HomeHero.hideWatched(connection.watchedIDs, continueWatching: &loaded.continueWatching, nextUp: &loaded.nextUp, heroNextUps: &heroNextUps)
            rows = loaded
            // the next first-load skeleton shows as many Continue Watching cards
            SkeletonRows.counts["continue-watching"] = loaded.continueWatching.count
            failure = nil
            reloadFailure = nil
            // the rows show at once, and each hero's Play and Details fill in as its lookup lands
            await withTaskGroup(of: (id: String, nextUp: BaseItemDto?, title: DetailsTitle?).self) { group in
                for hero in heroes {
                    guard let id = hero.item.id else { continue }
                    let item = hero.item
                    group.addTask {
                        // a failed next up leaves a series hero with Details only instead of failing Home
                        let next: BaseItemDto? = if item.type == .series { try? await service.nextUp(seriesID: id) } else { nil }
                        // one series fetch for an episode hero; a failed one leaves the hero with Play only
                        let title: DetailsTitle? = if item.type == .episode { try? await DetailsTitle.resolve(item, service: service) } else { nil }
                        return (id, next, title)
                    }
                }
                for await lookup in group {
                    // a newer load owns the heroes now
                    guard started == generation else {
                        group.cancelAll()
                        return
                    }
                    // a Watched mark that landed during the lookup keeps its episode off the hero's Play
                    heroNextUps[lookup.id] = lookup.nextUp.flatMap { $0.id.map(connection.watchedIDs.contains) == true ? nil : $0 }
                    heroTitles[lookup.id] = lookup.title
                }
            }
        } catch {
            // leaving Home cancels the load, which is no failure
            guard !Task.isCancelled else { return }
            if await connection.handleFailure(error) { return }
            // a load a newer one overtook publishes no error over the newer rows
            guard started == generation else { return }
            if rows == nil {
                failure = error.localizedDescription
            } else {
                reloadFailure = error.localizedDescription
            }
        }
    }
}
