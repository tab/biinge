import JellyfinAPI
import Observation

/// Holds the user's ready-to-watch queue and Jellyfin's rows, kept outside the sheet so reopening it shows the last ones while the refresh runs
@MainActor
@Observable
final class UpNextStore {
    private(set) var upNext: UpNext?
    /// Jellyfin's resume list, empty while Jellyfin isn't connected
    private(set) var continueWatching: [BaseItemDto] = []
    /// Jellyfin's Next Up episodes, empty while Jellyfin isn't connected
    private(set) var nextUp: [BaseItemDto] = []
    private(set) var isLoading = false
    /// The last load's error (the tracked queue's first, then Jellyfin's), nil after a load that succeeds
    private(set) var loadError: (any Error)?

    let connection: JellyfinConnection
    private let apiClient: APIClient

    init(apiClient: APIClient, connection: JellyfinConnection) {
        self.apiClient = apiClient
        self.connection = connection
    }

    var sections: [UpNextSection] {
        // Jellyfin may still report a title biinge just marked watched, and a failed mark brings its card back
        UpNextSection.compose(
            continueWatching: continueWatching.filter { $0.id.map(connection.watchedIDs.contains) != true },
            nextUp: nextUp.filter { $0.id.map(connection.watchedIDs.contains) != true },
            tracked: upNext
        )
    }

    /// The sheet's state, nil while it has a section to show (a failed load shows its error, never the empty state)
    var state: LoadState? {
        LoadState(hasLoaded: upNext != nil, isEmpty: sections.isEmpty, loadError: loadError)
    }

    /// Loads the tracked queue and, while Jellyfin is connected, its resume list and Next Up together; a revoked token disconnects and drops the Jellyfin rows
    func load() async {
        isLoading = true
        defer { isLoading = false }
        let service = connection.service
        async let tracked = apiClient.upNext()
        async let resume = service?.page(of: .continueWatching, startIndex: 0, limit: 20)
        async let next = service?.page(of: .nextUp, startIndex: 0, limit: 20)
        var failure: (any Error)?
        var loaded: UpNext?
        do {
            loaded = try await tracked
            // a tracked queue with content shows at once, so a slow Jellyfin can't hold it behind a spinner
            if !Task.isCancelled, let loaded, !UpNextSection.compose(continueWatching: [], nextUp: [], tracked: loaded).isEmpty {
                upNext = loaded
            }
        } catch {
            failure = error
        }
        var rows: (continueWatching: [BaseItemDto], nextUp: [BaseItemDto])?
        do {
            let (resumed, upcoming) = try await (resume, next)
            rows = (resumed?.items ?? [], upcoming?.items ?? [])
        } catch {
            if await connection.handleFailure(error) {
                rows = ([], [])
            } else {
                failure = failure ?? error
            }
        }
        // closing the sheet cancels the load, which is no failure
        guard !Task.isCancelled else { return }
        // both land together, so the empty state never shows while the other half is still loading
        if let loaded { upNext = loaded }
        if let rows {
            continueWatching = rows.continueWatching
            // the next loading skeleton shows as many Continue Watching cards
            SkeletonRows.counts["continue-watching"] = continueWatching.count
            nextUp = rows.nextUp
        }
        loadError = failure
    }
}

/// One Up Next section with something to show
enum UpNextSection {
    case continueWatching([BaseItemDto])
    case nextUp([BaseItemDto])
    case episodes([UpNextEpisode])
    case movies([UpNextMovie])
    case games([UpNextGame])

    var title: String {
        switch self {
        case .continueWatching: "Continue Watching"
        case .nextUp: "Next Episodes"
        case .episodes: "New Episodes"
        case .movies: "Movies"
        case .games: "Games"
        }
    }

    /// The non-empty sections in the sheet's order: Jellyfin's Continue Watching and Next Up, then the tracked episodes, movies and games
    static func compose(continueWatching: [BaseItemDto], nextUp: [BaseItemDto], tracked: UpNext?) -> [UpNextSection] {
        var sections: [UpNextSection] = []
        if !continueWatching.isEmpty { sections.append(.continueWatching(continueWatching)) }
        if !nextUp.isEmpty { sections.append(.nextUp(nextUp)) }
        if let tracked {
            if !tracked.episodes.isEmpty { sections.append(.episodes(tracked.episodes)) }
            if !tracked.movies.isEmpty { sections.append(.movies(tracked.movies)) }
            if !tracked.games.isEmpty { sections.append(.games(tracked.games)) }
        }
        return sections
    }
}
