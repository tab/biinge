import Observation

/// Holds the user's TV library (want / watching / watched), mirroring the RN TvContext.
@MainActor
@Observable
final class TvStore {
    private(set) var wantShows: [LibrarySeries] = []
    private(set) var watchingShows: [LibrarySeries] = []
    private(set) var watchedShows: [LibrarySeries] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

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
        (wantShows + watchingShows + watchedShows).first(where: { $0.id == id })?.pinned ?? false
    }

    /// Marks the library stale so the tab reloads next time it appears (used after
    /// episode marking changes a show's derived state on the server).
    func invalidate() {
        hasLoaded = false
    }

    // MARK: - Mutations

    /// Move a show into `target` (want/watching/watched); tapping the current
    /// state removes it.
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
        do {
            if current == target {
                try await apiClient.deleteSeries(id: id)
                removeLocal(id: id)
            } else if current == nil {
                _ = try await apiClient.createSeries(
                    CreateSeriesBody(
                        id: id, title: title, posterPath: posterPath,
                        seasonsCount: seasonsCount, episodesCount: episodesCount,
                        status: status, state: target.rawValue
                    )
                )
                insertLocal(LibrarySeries(
                    id: id, title: title, posterPath: posterPath, pinned: false,
                    state: target, episodesCount: episodesCount, watchedEpisodesCount: 0
                ))
            } else {
                _ = try await apiClient.updateSeries(id: id, UpdateSeriesBody(state: target.rawValue, pinned: isPinned(id: id)))
                moveLocal(id: id, to: target)
            }
        } catch {
            await load()
        }
    }

    func setPinned(id: Int, pinned: Bool) async {
        guard let current = currentState(id: id) else { return }
        setPinnedLocal(id: id, pinned: pinned)
        do {
            _ = try await apiClient.updateSeries(id: id, UpdateSeriesBody(state: current.rawValue, pinned: pinned))
        } catch {
            await load() // reconcile exact server ordering only if the write failed
        }
    }

    private func insertLocal(_ show: LibrarySeries) {
        switch show.state {
        case .want: wantShows.insert(show, at: 0)
        case .watching: watchingShows.insert(show, at: 0)
        case .watched: watchedShows.insert(show, at: 0)
        case .none: break
        }
    }

    /// Move an already-tracked show to a new state segment, preserving its counts.
    private func moveLocal(id: Int, to target: WatchState) {
        guard let existing = (wantShows + watchingShows + watchedShows).first(where: { $0.id == id }) else { return }
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

    /// Flip a show's pinned flag and float pinned items to the top (stable), matching
    /// the server's `pinned DESC` ordering without a full reload.
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

    /// Reflect a mark/unmark from a detail screen in the cached grid: update the
    /// show's watched-episode count (drives the progress badge) and move it to the
    /// segment matching its new derived state — no full library reload. Falls back
    /// to invalidation if the show isn't cached yet (e.g. it was just tracked).
    func applyProgress(id: Int, state: WatchState, watchedEpisodesCount: Int) {
        guard let current = (wantShows + watchingShows + watchedShows).first(where: { $0.id == id }) else {
            invalidate()
            return
        }
        let updated = LibrarySeries(
            id: current.id, title: current.title, posterPath: current.posterPath,
            pinned: current.pinned, state: state,
            episodesCount: current.episodesCount, watchedEpisodesCount: watchedEpisodesCount
        )
        if current.state == state {
            replaceInPlace(updated)
        } else {
            removeLocal(id: id)
            insertLocal(updated)
        }
    }

    private func replaceInPlace(_ show: LibrarySeries) {
        if let i = wantShows.firstIndex(where: { $0.id == show.id }) { wantShows[i] = show }
        if let i = watchingShows.firstIndex(where: { $0.id == show.id }) { watchingShows[i] = show }
        if let i = watchedShows.firstIndex(where: { $0.id == show.id }) { watchedShows[i] = show }
    }

    /// Push fresher poster/title from a detail load into the cached grid item so the
    /// grid reflects the server's read-repair without waiting for a full reload.
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
