import Foundation
import JellyfinAPI
import Observation

/// One Jellyfin list paged into a grid on every platform: the items loaded so far, the list's total and the errors, with the loads that change them
@MainActor
@Observable
final class PagedLibrary {
    private let connection: JellyfinConnection
    /// The list the pages come from (a new one shows its remembered first page or empties the grid, and drops any page in flight, keeping the total until its first page lands)
    var list: LibraryList {
        didSet {
            generation += 1
            let first = connection.firstPages[list]
            items = first?.items ?? []
            nextIndex = items.count
            total = first?.total ?? total
            pageFailure = nil
            isRemembered = first != nil
        }
    }
    private(set) var items: [BaseItemDto]
    /// The list's total, nil until the first page lands
    private(set) var total: Int?
    /// The first load's error message, nil once a page is on screen
    private(set) var failure: String?
    /// A failed page's error message, shown under the items already on screen (isFirstPage makes Retry load the first page again rather than the next)
    private(set) var pageFailure: (message: String, isFirstPage: Bool)?
    /// Set while a next page loads
    private(set) var isLoading = false
    /// The server index of the next page, which counts the items a page skipped as already loaded
    private var nextIndex: Int
    /// Bumped by every load and new list, so a page that started before them drops its result and its error
    private var generation = 0
    /// Set while the items are a remembered first page that no load has replaced and no later page has grown
    private var isRemembered: Bool

    /// The items a grid shows: all of them, less in Continue Watching and Next Up any title biinge marked watched, which Jellyfin may still report unplayed (a failed mark brings its card back)
    var shown: [BaseItemDto] {
        guard list == .continueWatching || list == .nextUp else { return items }
        return items.filter { $0.id.map(connection.watchedIDs.contains) != true }
    }

    /// The list's total less the items `shown` leaves out, so hiding the last card shows the empty state
    var shownTotal: Int? {
        total.map { $0 - (items.count - shown.count) }
    }

    /// A grid of the list, showing the first page an earlier visit remembered until a load replaces it
    init(connection: JellyfinConnection, list: LibraryList) {
        self.connection = connection
        self.list = list
        let first = connection.firstPages[list]
        items = first?.items ?? []
        nextIndex = first?.items.count ?? 0
        total = first?.total
        isRemembered = first != nil
    }

    /// Loads a grid on its first appearance, or a remembered first page in place of the items on screen (a later appearance keeps the pages it has)
    func loadIfNeeded() async {
        if total == nil {
            await loadMore()
        } else if isRemembered {
            await load()
        }
    }

    /// Empties the grid back to its loading state and drops any page in flight (Retry on the empty and offline states, before the load)
    func clear() {
        generation += 1
        items = []
        nextIndex = 0
        total = nil
        failure = nil
        pageFailure = nil
        isRemembered = false
    }

    /// Empties the grid back to its loading state, then loads the first page
    func reload() async {
        clear()
        await load()
    }

    /// Loads the first page in place of the items on screen, which stay until it lands (a remembered page's load keeps the pages appended meanwhile), with `alongside` running beside it so both land or neither does (the iPhone Library's rows above its grid); returns whether the page landed
    @discardableResult
    func load(alongside: @MainActor () async throws -> Void = {}) async -> Bool {
        // a revoked token disconnects, a failure with no items on screen shows the offline state and any other the error under the items
        guard let service = connection.service else { return false }
        generation += 1
        let started = generation
        let session = connection.generation
        let list = list
        let kept = isRemembered ? items.count : nil
        do {
            async let page = service.page(of: list, startIndex: 0, limit: 60)
            try await alongside()
            let first = try await page
            // a new list, a later load or a disconnect replaced this load
            guard started == generation, session == connection.generation, !Task.isCancelled else { return false }
            if let kept {
                // a page appended while this request was out stays after the first page, less any item it now holds
                let refreshed = Set(first.items.map(\.id))
                items = first.items + items.dropFirst(kept).filter { !refreshed.contains($0.id) }
                nextIndex = first.items.count + (nextIndex - kept)
            } else {
                items = first.items
                nextIndex = first.items.count
            }
            total = first.total
            failure = nil
            pageFailure = nil
            isRemembered = false
            connection.firstPages[list] = first
            return true
        } catch {
            // leaving the screen cancels the load, which is no failure, and a replaced load's failure no longer applies
            guard started == generation, session == connection.generation, !Task.isCancelled else { return false }
            if await connection.handleFailure(error) { return false }
            // with no items on screen the failure takes the whole screen, never the empty state
            if (total ?? 0) == 0 {
                failure = error.localizedDescription
            } else {
                pageFailure = (error.localizedDescription, true)
            }
            return false
        }
    }

    /// Appends the next 60 items, or loads the first page while the total is unknown; a revoked token disconnects, a failed first page shows the offline state and a later one the error with Retry
    func loadMore() async {
        guard !isLoading, let service = connection.service, nextIndex < total ?? .max else { return }
        let started = generation
        let session = connection.generation
        let offset = nextIndex
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await service.page(of: list, startIndex: offset, limit: 60)
            // a new list, a disconnect or a load during the request replaced the grid (a load that began before this page shares its generation, so the offset tells)
            guard started == generation, session == connection.generation, offset == nextIndex else { return }
            nextIndex += page.items.count
            // a list that shifted between pages can repeat an item, which the grid's IDs can't hold twice
            let loaded = Set(items.map(\.id))
            items += page.items.filter { !loaded.contains($0.id) }
            total = page.total
            failure = nil
            pageFailure = nil
            isRemembered = false
            if offset == 0 { connection.firstPages[list] = page }
        } catch {
            // leaving the screen cancels the load, which is no failure, and a replaced page's failure no longer applies
            guard started == generation, session == connection.generation, offset == nextIndex, !Task.isCancelled else { return }
            if await connection.handleFailure(error) { return }
            if total == nil {
                failure = error.localizedDescription
            } else {
                pageFailure = (error.localizedDescription, false)
            }
        }
    }

    /// Loads every page already on screen again in one request, so the cards show new progress (a failure keeps the old ones, and a revoked token disconnects)
    func refresh() async {
        guard let service = connection.service, !items.isEmpty else { return }
        let start = nextIndex
        let kept = items.count
        do {
            let page = try await service.page(of: list, startIndex: 0, limit: start)
            // a page appended while this request was out stays after the refreshed ones, less any item they now hold
            let refreshed = Set(page.items.map(\.id))
            items = page.items + items.dropFirst(kept).filter { !refreshed.contains($0.id) }
            nextIndex = page.items.count + (nextIndex - start)
            total = page.total
        } catch {
            _ = await connection.handleFailure(error)
        }
    }
}

extension PagedLibrary {
    /// A library's genres for its Genre menu, which outlast the grid's new sorts, filters and genres
    @MainActor
    @Observable
    final class Genres {
        private let connection: JellyfinConnection
        private let type: BaseItemKind
        /// The genre names, empty until they load
        private(set) var names: [String]
        /// Set while the last load failed, when a Retry stands in for the Genre menu
        private(set) var failed = false

        /// The genres of the library of this item type (movies or series)
        init(connection: JellyfinConnection, type: BaseItemKind) {
            self.connection = connection
            self.type = type
            names = connection.genres[type] ?? []
        }

        /// Loads the genres; a revoked token disconnects, and any other failure sets `failed`
        func load() async {
            guard let service = connection.service else { return }
            let session = connection.generation
            do {
                names = try await service.genres(of: type)
                failed = false
                // names from before a disconnect stay out of the next session's memory
                if session == connection.generation { connection.genres[type] = names }
            } catch {
                guard !Task.isCancelled else { return }
                _ = await connection.handleFailure(error)
                failed = true
            }
        }
    }
}
