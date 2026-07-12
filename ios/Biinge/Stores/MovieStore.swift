import Observation

/// Holds the user's movie library (want / watched), mirroring the RN MovieContext.
@MainActor
@Observable
final class MovieStore {
    private(set) var wantMovies: [LibraryMovie] = []
    private(set) var watchedMovies: [LibraryMovie] = []
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
        async let watched = fetch(type: "watched")
        let (wantResult, watchedResult) = await (want, watched)
        if let wantResult { wantMovies = wantResult }
        if let watchedResult { watchedMovies = watchedResult }
        isLoading = false
        hasLoaded = true
    }

    private func fetch(type: String) async -> [LibraryMovie]? {
        try? await apiClient.movies(type: type).data
    }

    // MARK: - Membership

    func currentState(id: Int) -> WatchState? {
        if wantMovies.contains(where: { $0.id == id }) { return .want }
        if watchedMovies.contains(where: { $0.id == id }) { return .watched }
        return nil
    }

    func isPinned(id: Int) -> Bool {
        (wantMovies + watchedMovies).first(where: { $0.id == id })?.pinned ?? false
    }

    // MARK: - Mutations (optimistic; resync from the server on failure)

    /// Move a movie into `target` (want/watched); tapping the current state removes it.
    func toggle(id: Int, title: String, posterPath: String, runtime: Int, target: WatchState) async {
        let current = currentState(id: id)
        let pinned = isPinned(id: id)
        do {
            if current == target {
                try await apiClient.deleteMovie(id: id)
                removeLocal(id: id)
            } else if current == nil {
                _ = try await apiClient.createMovie(
                    CreateMovieBody(id: id, title: title, posterPath: posterPath, runtime: runtime, state: target.rawValue)
                )
                insertLocal(LibraryMovie(id: id, title: title, posterPath: posterPath, pinned: false, state: target))
            } else {
                _ = try await apiClient.updateMovie(id: id, UpdateMovieBody(state: target.rawValue, pinned: pinned))
                removeLocal(id: id)
                insertLocal(LibraryMovie(id: id, title: title, posterPath: posterPath, pinned: pinned, state: target))
            }
        } catch {
            await load()
        }
    }

    func setPinned(id: Int, pinned: Bool) async {
        guard let current = currentState(id: id) else { return }
        do {
            _ = try await apiClient.updateMovie(id: id, UpdateMovieBody(state: current.rawValue, pinned: pinned))
            await load() // reload for server-side pinned-first ordering
        } catch {
            await load()
        }
    }

    private func insertLocal(_ movie: LibraryMovie) {
        switch movie.state {
        case .want: wantMovies.insert(movie, at: 0)
        case .watched: watchedMovies.insert(movie, at: 0)
        default: break
        }
    }

    private func removeLocal(id: Int) {
        wantMovies.removeAll { $0.id == id }
        watchedMovies.removeAll { $0.id == id }
    }

    /// Push fresher poster/title from a detail load into the cached grid item so the
    /// grid reflects the server's read-repair without waiting for a full reload.
    func refreshMetadata(id: Int, title: String, posterPath: String) {
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &wantMovies)
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &watchedMovies)
    }

    private func applyMetadata(id: Int, title: String, posterPath: String, to list: inout [LibraryMovie]) {
        guard !posterPath.isEmpty,
              let index = list.firstIndex(where: { $0.id == id }),
              list[index].posterPath != posterPath || list[index].title != title else { return }
        let existing = list[index]
        list[index] = LibraryMovie(
            id: existing.id, title: title, posterPath: posterPath,
            pinned: existing.pinned, state: existing.state
        )
    }
}
