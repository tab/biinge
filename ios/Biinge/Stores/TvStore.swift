import Observation

/// Holds the user's TV library (want / watching / watched), mirroring the RN TvContext
@MainActor
@Observable
final class TvStore {
    private(set) var wantShows: [LibrarySeries] = []
    private(set) var watchingShows: [LibrarySeries] = []
    private(set) var watchedShows: [LibrarySeries] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Per-show watch progress shared by the detail screens and the grid
    private(set) var progressByShow: [Int: WatchProgress] = [:]

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        isLoading = true
        async let want = fetch(type: "want")
        async let watching = fetch(type: "watching")
        async let watched = fetch(type: "watched")
        let (wantResult, watchingResult, watchedResult) = await (want, watching, watched)
        if let wantResult { wantShows = wantResult }
        if let watchingResult { watchingShows = watchingResult }
        if let watchedResult { watchedShows = watchedResult }
        isLoading = false
        hasLoaded = true
    }

    private func fetch(type: String) async -> [LibrarySeries]? {
        try? await apiClient.series(type: type).data
    }

    // MARK: - Membership

    func currentState(id: Int) -> WatchState? {
        if wantShows.contains(where: { $0.id == id }) { return .want }
        if watchingShows.contains(where: { $0.id == id }) { return .watching }
        if watchedShows.contains(where: { $0.id == id }) { return .watched }
        return nil
    }

    func isPinned(id: Int) -> Bool {
        firstMatch(id: id)?.pinned ?? false
    }

    /// Locate a show in any segment without concatenating (copying) the lists
    private func firstMatch(id: Int) -> LibrarySeries? {
        wantShows.first { $0.id == id }
            ?? watchingShows.first { $0.id == id }
            ?? watchedShows.first { $0.id == id }
    }

    func progress(id: Int) -> WatchProgress? {
        progressByShow[id]
    }

    // MARK: - Mutations (optimistic: local first, serialized server write after)

    /// Move a show into `target`; tapping the current state removes it
    func toggle(
        id: Int,
        title: String,
        posterPath: String,
        seasonsCount: Int,
        episodesCount: Int,
        status: String,
        target: WatchState
    ) async {
        let current = currentState(id: id)
        if current == target {
            removeLocal(id: id)
            // untracking deletes episode rows server-side, so open sheets drop their checkmarks too
            progressByShow[id] = WatchProgress(id: id, state: .none, trackedState: nil, watchedSeasons: [], watchedEpisodes: [])
            enqueueWrite { [apiClient] in
                try await apiClient.deleteSeries(id: id)
            }
        } else if current == nil {
            insertLocal(LibrarySeries(
                id: id, title: title, posterPath: posterPath, pinned: false,
                state: target, episodesCount: episodesCount, watchedEpisodesCount: 0
            ))
            retrackProgress(id: id, state: target)
            enqueueWrite { [apiClient] in
                _ = try await apiClient.createSeries(
                    CreateSeriesBody(
                        id: id, title: title, posterPath: posterPath,
                        seasonsCount: seasonsCount, episodesCount: episodesCount,
                        status: status, state: target.rawValue
                    )
                )
            }
        } else {
            let pinned = isPinned(id: id)
            moveLocal(id: id, to: target)
            retrackProgress(id: id, state: target)
            enqueueWrite { [apiClient] in
                _ = try await apiClient.updateSeries(id: id, UpdateSeriesBody(state: target.rawValue, pinned: pinned))
            }
        }
    }

    /// Explicit tracking updates the cached progress; unmark-all reverts to this state
    private func retrackProgress(id: Int, state: WatchState) {
        guard let cached = progressByShow[id] else { return }
        progressByShow[id] = WatchProgress(
            id: cached.id, state: state, trackedState: state,
            watchedSeasons: cached.watchedSeasons, watchedEpisodes: cached.watchedEpisodes
        )
    }

    func setPinned(id: Int, pinned: Bool) async {
        guard let current = currentState(id: id) else { return }
        setPinnedLocal(id: id, pinned: pinned)
        enqueueWrite { [apiClient] in
            _ = try await apiClient.updateSeries(id: id, UpdateSeriesBody(state: current.rawValue, pinned: pinned))
        }
    }

    // MARK: - Write queue

    private var writeChain: Task<Void, Never>?
    private var pendingWrites = 0
    private var writeFailed = false

    /// Runs server writes in submission order; a failure resyncs once the queue drains
    private func enqueueWrite(_ op: @escaping () async throws -> Void) {
        pendingWrites += 1
        let prior = writeChain
        writeChain = Task {
            await prior?.value
            do {
                try await op()
            } catch {
                writeFailed = true
            }
            pendingWrites -= 1
            if pendingWrites == 0, writeFailed {
                writeFailed = false
                await load()
            }
        }
    }

    private func insertLocal(_ show: LibrarySeries) {
        switch show.state {
        case .want: wantShows.insert(show, at: 0)
        case .watching: watchingShows.insert(show, at: 0)
        case .watched: watchedShows.insert(show, at: 0)
        default: break
        }
    }

    /// Move an already-tracked show to a new state segment, preserving its counts
    private func moveLocal(id: Int, to target: WatchState) {
        guard let existing = firstMatch(id: id) else { return }
        removeLocal(id: id)
        insertLocal(LibrarySeries(
            id: existing.id, title: existing.title, posterPath: existing.posterPath,
            pinned: existing.pinned, state: target,
            episodesCount: existing.episodesCount, watchedEpisodesCount: existing.watchedEpisodesCount
        ))
    }

    private func setPinnedLocal(id: Int, pinned: Bool) {
        repartition(&wantShows, id: id, pinned: pinned)
        repartition(&watchingShows, id: id, pinned: pinned)
        repartition(&watchedShows, id: id, pinned: pinned)
    }

    /// Flip a show's pinned flag and float pinned items to the top, matching the server's ordering
    private func repartition(_ list: inout [LibrarySeries], id: Int, pinned: Bool) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let existing = list[index]
        list[index] = LibrarySeries(
            id: existing.id, title: existing.title, posterPath: existing.posterPath,
            pinned: pinned, state: existing.state,
            episodesCount: existing.episodesCount, watchedEpisodesCount: existing.watchedEpisodesCount
        )
        list = list.filter { $0.pinned } + list.filter { !$0.pinned }
    }

    private func removeLocal(id: Int) {
        wantShows.removeAll { $0.id == id }
        watchingShows.removeAll { $0.id == id }
        watchedShows.removeAll { $0.id == id }
    }

    /// Caches progress for the detail screens and reflects it into the grid, inserting or removing the show as needed
    func apply(_ value: WatchProgress, id: Int, title: String, posterPath: String, episodesCount: Int, pinned: Bool) {
        progressByShow[id] = value
        let watchedCount = value.watchedEpisodes.count
        if let current = firstMatch(id: id) {
            let updated = LibrarySeries(
                id: current.id, title: current.title, posterPath: current.posterPath,
                pinned: current.pinned, state: value.state,
                episodesCount: current.episodesCount, watchedEpisodesCount: watchedCount
            )
            if current.state == value.state {
                replaceInPlace(updated)
            } else {
                removeLocal(id: id)
                insertLocal(updated) // insertLocal ignores .none, so this removes
            }
        } else if value.state != .none {
            insertLocal(LibrarySeries(
                id: id, title: title, posterPath: posterPath, pinned: pinned,
                state: value.state, episodesCount: episodesCount, watchedEpisodesCount: watchedCount
            ))
        }
    }

    private func replaceInPlace(_ show: LibrarySeries) {
        if let i = wantShows.firstIndex(where: { $0.id == show.id }) { wantShows[i] = show }
        if let i = watchingShows.firstIndex(where: { $0.id == show.id }) { watchingShows[i] = show }
        if let i = watchedShows.firstIndex(where: { $0.id == show.id }) { watchedShows[i] = show }
    }

    /// Push fresher poster/title from a detail load into the cached grid item
    func refreshMetadata(id: Int, title: String, posterPath: String) {
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &wantShows)
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &watchingShows)
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &watchedShows)
    }

    private func applyMetadata(id: Int, title: String, posterPath: String, to list: inout [LibrarySeries]) {
        guard !posterPath.isEmpty,
              let index = list.firstIndex(where: { $0.id == id }),
              list[index].posterPath != posterPath || list[index].title != title else { return }
        let existing = list[index]
        list[index] = LibrarySeries(
            id: existing.id, title: title, posterPath: posterPath,
            pinned: existing.pinned, state: existing.state,
            episodesCount: existing.episodesCount, watchedEpisodesCount: existing.watchedEpisodesCount
        )
    }
}
