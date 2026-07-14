import Observation

/// Holds the user's movie library (want / watched), mirroring the RN MovieContext
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
        firstMatch(id: id)?.pinned ?? false
    }

    /// Locate a movie in either segment without concatenating (copying) the lists
    private func firstMatch(id: Int) -> LibraryMovie? {
        wantMovies.first { $0.id == id } ?? watchedMovies.first { $0.id == id }
    }

    // MARK: - Mutations (optimistic: local first, serialized server write after)

    /// Move a movie into `target` (want/watched); tapping the current state removes it
    func toggle(id: Int, title: String, posterPath: String, runtime: Int, target: WatchState) async {
        let current = currentState(id: id)
        let pinned = isPinned(id: id)
        if current == target {
            removeLocal(id: id)
            enqueueWrite { [apiClient] in
                try await apiClient.deleteMovie(id: id)
            }
        } else if current == nil {
            insertLocal(LibraryMovie(id: id, title: title, posterPath: posterPath, pinned: false, state: target))
            enqueueWrite { [apiClient] in
                _ = try await apiClient.createMovie(
                    CreateMovieBody(id: id, title: title, posterPath: posterPath, runtime: runtime, state: target.rawValue)
                )
            }
        } else {
            removeLocal(id: id)
            insertLocal(LibraryMovie(id: id, title: title, posterPath: posterPath, pinned: pinned, state: target))
            enqueueWrite { [apiClient] in
                _ = try await apiClient.updateMovie(id: id, UpdateMovieBody(state: target.rawValue, pinned: pinned))
            }
        }
    }

    func setPinned(id: Int, pinned: Bool) async {
        guard let current = currentState(id: id) else { return }
        setPinnedLocal(id: id, pinned: pinned)
        enqueueWrite { [apiClient] in
            _ = try await apiClient.updateMovie(id: id, UpdateMovieBody(state: current.rawValue, pinned: pinned))
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

    private func setPinnedLocal(id: Int, pinned: Bool) {
        repartition(&wantMovies, id: id, pinned: pinned)
        repartition(&watchedMovies, id: id, pinned: pinned)
    }

    /// Flip a movie's pinned flag and float pinned items to the top, matching the server's ordering
    private func repartition(_ list: inout [LibraryMovie], id: Int, pinned: Bool) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let existing = list[index]
        list[index] = LibraryMovie(
            id: existing.id, title: existing.title, posterPath: existing.posterPath,
            pinned: pinned, state: existing.state
        )
        list = list.filter { $0.pinned } + list.filter { !$0.pinned }
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

    /// Push fresher poster/title from a detail load into the cached grid item
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
