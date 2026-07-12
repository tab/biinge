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

    /// Toggle a show's "want" membership. Shows in watching/watched move to want.
    func toggleWant(
        id: Int,
        title: String,
        posterPath: String,
        seasonsCount: Int,
        episodesCount: Int,
        status: String
    ) async {
        let current = currentState(id: id)
        do {
            if current == .want {
                try await apiClient.deleteSeries(id: id)
                removeLocal(id: id)
            } else if current == nil {
                _ = try await apiClient.createSeries(
                    CreateSeriesBody(
                        id: id, title: title, posterPath: posterPath,
                        seasonsCount: seasonsCount, episodesCount: episodesCount,
                        status: status, state: WatchState.want.rawValue
                    )
                )
                insertLocal(LibrarySeries(
                    id: id, title: title, posterPath: posterPath, pinned: false,
                    state: .want, episodesCount: episodesCount, watchedEpisodesCount: 0
                ))
            } else {
                _ = try await apiClient.updateSeries(id: id, UpdateSeriesBody(state: WatchState.want.rawValue, pinned: isPinned(id: id)))
                await load()
            }
        } catch {
            await load()
        }
    }

    func remove(id: Int) async {
        do {
            try await apiClient.deleteSeries(id: id)
            removeLocal(id: id)
        } catch {
            await load()
        }
    }

    func setPinned(id: Int, pinned: Bool) async {
        guard let current = currentState(id: id) else { return }
        do {
            _ = try await apiClient.updateSeries(id: id, UpdateSeriesBody(state: current.rawValue, pinned: pinned))
            await load()
        } catch {
            await load()
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

    private func removeLocal(id: Int) {
        wantShows.removeAll { $0.id == id }
        watchingShows.removeAll { $0.id == id }
        watchedShows.removeAll { $0.id == id }
    }
}
