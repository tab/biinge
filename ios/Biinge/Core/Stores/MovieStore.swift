import Observation

/// Holds the user's movie library (want / watched), mirroring the RN MovieContext
@MainActor
@Observable
final class MovieStore {
    private(set) var wantMovies: [LibraryMovie] = []
    private(set) var watchedMovies: [LibraryMovie] = []
    private(set) var isLoading = false
    /// Set only after a load in which every list arrived
    private(set) var hasLoaded = false
    /// The last load's failure, nil once a load succeeds (the lists keep what an earlier load brought)
    private(set) var loadError: (any Error)?

    /// The first load in flight, which callers arriving during it share so a cold launch fetches once
    private var firstLoad: Task<Void, Never>?

    private let apiClient: APIClient
    /// How long a removal waits for Undo before its DELETE goes out
    private let undoWindow: Duration

    init(apiClient: APIClient, undoWindow: Duration = Toast.undoWindow) {
        self.apiClient = apiClient
        self.undoWindow = undoWindow
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        if let firstLoad {
            await firstLoad.value
            return
        }
        // a task of its own, so leaving the screen that started it doesn't cancel it for the others waiting
        let load = Task { await self.load() }
        firstLoad = load
        await load.value
        firstLoad = nil
    }

    func load() async {
        // the server may not hold the pending writes yet, so the queue loads once it drains
        guard pendingWrites == 0 else {
            reloadAfterWrites = true
            return
        }
        let started = writesEnqueued
        isLoading = true
        defer { isLoading = false }
        do {
            async let want = apiClient.movies(type: "want").data
            async let watched = apiClient.movies(type: "watched").data
            let lists = try await (want, watched)
            // a write that went out during the fetch may be missing from it, so the lists wait for a load after it
            guard writesEnqueued == started else {
                if pendingWrites > 0 { reloadAfterWrites = true } else { await load() }
                return
            }
            (wantMovies, watchedMovies) = lists
            // the server still lists a movie waiting out its Undo window, and its entry there (after any earlier write failed) is what Undo restores
            if let pending = pendingRemoval {
                if let movie = firstMatch(id: pending.movie.id) {
                    pendingRemoval?.movie = movie
                    pendingRemoval?.index = (movie.state == .want ? wantMovies : watchedMovies).firstIndex { $0.id == movie.id } ?? 0
                } else {
                    // an earlier write that failed never listed it, so there is nothing to remove or bring back
                    pendingRemoval = nil
                    pending.outcome.cancel()
                }
                removeLocal(id: pending.movie.id)
            }
            loadError = nil
            hasLoaded = true
        } catch {
            // a screen that went away cancels its load, which is no failure to show
            guard !Task.isCancelled else { return }
            loadError = error
        }
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

    /// Moves the movie into `target`, or removes it when it already sits there (returns the move's or the removal's task)
    @discardableResult
    func toggle(id: Int, title: String, posterPath: String, runtime: Int, target: WatchState) async -> Task<Void, Never> {
        guard currentState(id: id) == target else {
            return await move(id: id, title: title, posterPath: posterPath, runtime: runtime, target: target)
        }
        return remove(id: id)
    }

    /// Hides the movie until its Undo window ends and the DELETE goes out (returns a task that ends after the resync a failure brings, or once Undo cancels it; nothing happens to a movie in no list)
    @discardableResult
    func remove(id: Int) -> Task<Void, Never> {
        guard let movie = firstMatch(id: id) else { return Task {} }
        // a new removal ends the Undo window of the one before it
        commitRemoval()
        let index = (movie.state == .want ? wantMovies : watchedMovies).firstIndex { $0.id == id } ?? 0
        removeLocal(id: id)
        removals += 1
        let number = removals
        let outcome = Task { () -> (any Error)? in
            do {
                try await Task.sleep(for: undoWindow)
            } catch {
                // Undo and an early commit end the removal before they cut the wait short, so any other cancel undoes it unsent
                if pendingRemoval?.number == number { undoRemoval(id: id) }
            }
            if pendingRemoval?.number == number { commitRemoval() }
            guard let commit = removalCommits.removeValue(forKey: number) else { return nil }
            return await commit.value
        }
        pendingRemoval = PendingRemoval(
            movie: movie, index: index, number: number, session: apiClient.authManager.sessionsEnded, outcome: outcome
        )
        return Task { _ = await outcome.value }
    }

    /// Moves the movie into `target`, unpinned unless `target` is Want (nothing happens when it already sits there; returns a task that ends once the queue drains or after the resync a failure brings)
    @discardableResult
    func move(id: Int, title: String, posterPath: String, runtime: Int, target: WatchState) async -> Task<Void, Never> {
        // the server takes the pending removal before this write on the same movie
        if pendingRemoval?.movie.id == id { commitRemoval() }
        let current = currentState(id: id)
        guard current != target else { return Task {} }
        // only Want pins, so a move to Watched unpins
        let pinned = target.isPinnable && isPinned(id: id)
        if current == nil {
            confirmed[id, default: Confirmed(movie: nil, index: 0, writes: 0)].writes += 1
            // the next load brings the Jellyfin item, which only the API can match
            let added = LibraryMovie(id: id, title: title, posterPath: posterPath, pinned: false, state: target, jellyfinID: nil)
            insertLocal(added)
            var failure: (any Error)?
            let write = enqueueWrite { [apiClient] in
                defer {
                    self.confirmed[id]?.writes -= 1
                    if self.confirmed[id]?.writes == 0 { self.confirmed[id] = nil }
                }
                do {
                    _ = try await apiClient.createMovie(
                        CreateMovieBody(id: id, title: title, posterPath: posterPath, runtime: runtime, state: target.rawValue)
                    )
                    self.confirmed[id]?.movie = added
                    self.confirmed[id]?.index = 0
                } catch {
                    failure = error
                    // a later write on the movie carries the user's latest choice, and the last one puts back what the server holds, as the queue's resync may fail too
                    if self.confirmed[id]?.writes == 1 { self.restoreConfirmed(id: id) }
                    throw error
                }
            }
            addWrites[id] = Task { await write.value; return failure }
            return write
        } else {
            let previous = firstMatch(id: id)
            let index = (current == .want ? wantMovies : watchedMovies).firstIndex { $0.id == id } ?? 0
            confirmed[id, default: Confirmed(movie: previous, index: index, writes: 0)].writes += 1
            removeLocal(id: id)
            let moved = LibraryMovie(id: id, title: title, posterPath: posterPath, pinned: pinned, state: target, jellyfinID: previous?.jellyfinID)
            insertLocal(moved)
            var failure: (any Error)?
            let write = enqueueWrite { [apiClient] in
                defer {
                    self.confirmed[id]?.writes -= 1
                    if self.confirmed[id]?.writes == 0 { self.confirmed[id] = nil }
                }
                do {
                    _ = try await apiClient.updateMovie(id: id, UpdateMovieBody(state: target.rawValue, pinned: pinned))
                    self.confirmed[id]?.movie = moved
                    self.confirmed[id]?.index = 0
                } catch {
                    failure = error
                    // a later write on the movie carries the user's latest choice, and the last one puts back what the server holds, as the queue's resync may fail too
                    if self.confirmed[id]?.writes == 1 { self.restoreConfirmed(id: id) }
                    throw error
                }
            }
            addWrites[id] = Task { await write.value; return failure }
            return write
        }
    }

    /// Each movie's last add or move by its ID, ending with the write's failure once the queue has drained
    private var addWrites: [Int: Task<(any Error)?, Never>] = [:]

    /// A movie's entry as the server last confirmed it, while its adds, moves and removals are queued
    private struct Confirmed {
        /// Nil while the server lists no entry
        var movie: LibraryMovie?
        /// Where it sat in its list
        var index: Int
        /// How many of its writes are still queued
        var writes: Int
    }

    /// Each movie with an add, move or removal queued, by its ID
    private var confirmed: [Int: Confirmed] = [:]

    /// Puts the movie back as the server last confirmed it, or hands that entry to the removal waiting on it (drops the removal when the server lists none)
    private func restoreConfirmed(id: Int) {
        guard let entry = confirmed[id] else { return }
        if let pending = pendingRemoval, pending.movie.id == id {
            if let movie = entry.movie {
                pendingRemoval?.movie = movie
                pendingRemoval?.index = entry.index
            } else {
                pendingRemoval = nil
                pending.outcome.cancel()
            }
            return
        }
        removeLocal(id: id)
        guard let movie = entry.movie else { return }
        switch movie.state {
        case .want: wantMovies.insert(movie, at: min(entry.index, wantMovies.count))
        case .watched: watchedMovies.insert(movie, at: min(entry.index, watchedMovies.count))
        default: break
        }
    }

    /// Waits for the movie's last add or move to sync (returns its failure once the movie is back as it was, nil when it lands and when none waits)
    func addFailure(id: Int) async -> (any Error)? {
        await addWrites.removeValue(forKey: id)?.value
    }

    func setPinned(id: Int, pinned: Bool) async {
        guard let current = currentState(id: id) else { return }
        setPinnedLocal(id: id, pinned: pinned)
        enqueueWrite { [apiClient] in
            _ = try await apiClient.updateMovie(id: id, UpdateMovieBody(state: current.rawValue, pinned: pinned))
        }
    }

    // MARK: - Removal with Undo

    /// The movie a removal hid for its Undo window
    private struct PendingRemoval {
        var movie: LibraryMovie
        /// Where it sat in its list
        var index: Int
        /// Tells this removal from a later one of the same title
        let number: Int
        /// The session the removal began in, whose end drops its DELETE unsent
        let session: Int
        /// Ends with the removal, returning the commit's failure (nil when it lands or Undo cancels it)
        let outcome: Task<(any Error)?, Never>
    }

    /// The removal waiting out its Undo window, nil when none waits
    private var pendingRemoval: PendingRemoval?
    /// Counts every removal ever made, so a removal's wait can tell it is still the pending one
    private var removals = 0
    /// Each committed removal's DELETE by its number, ending with its failure once the resync has run
    private var removalCommits: [Int: Task<(any Error)?, Never>] = [:]

    /// Puts back the movie its pending removal hid, exactly as it was, and sends nothing (nothing happens once the removal has committed)
    func undoRemoval(id: Int) {
        guard let pending = pendingRemoval, pending.movie.id == id else { return }
        pendingRemoval = nil
        pending.outcome.cancel()
        switch pending.movie.state {
        case .want: wantMovies.insert(pending.movie, at: min(pending.index, wantMovies.count))
        case .watched: watchedMovies.insert(pending.movie, at: min(pending.index, watchedMovies.count))
        default: break
        }
    }

    /// Whether the movie's removal still waits out its Undo window (the Undo toast closes once it doesn't)
    func isRemovalPending(id: Int) -> Bool {
        pendingRemoval?.movie.id == id
    }

    /// Waits for the movie's pending removal to end (returns the commit's failure once the resync has brought the movie back, nil when it lands, on Undo and when none is pending)
    func removalFailure(id: Int) async -> (any Error)? {
        guard let pending = pendingRemoval, pending.movie.id == id else { return nil }
        return await pending.outcome.value
    }

    /// Sends the pending removal's DELETE now, ending its Undo window (a failure puts the movie back as the server holds it, unless a later write on it is queued)
    private func commitRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        let id = pending.movie.id
        confirmed[id, default: Confirmed(movie: pending.movie, index: pending.index, writes: 0)].writes += 1
        var failure: (any Error)?
        let write = enqueueWrite { [apiClient] in
            defer {
                self.confirmed[id]?.writes -= 1
                if self.confirmed[id]?.writes == 0 { self.confirmed[id] = nil }
            }
            // after a logout the token belongs to whoever signs in next, so the movie stays listed in the account that removed it
            guard pending.session == apiClient.authManager.sessionsEnded else { return }
            do {
                try await apiClient.deleteMovie(id: id, session: pending.session)
                self.confirmed[id]?.movie = nil
            } catch {
                failure = error
                // a later write on the movie carries the user's latest choice, and the last one puts back what the server holds, as the queue's resync may fail too
                if self.confirmed[id]?.writes == 1 { self.restoreConfirmed(id: id) }
                throw error
            }
        }
        removalCommits[pending.number] = Task { await write.value; return failure }
        pending.outcome.cancel()
    }

    // MARK: - Write queue

    private var writeChain: Task<Void, Never>?
    private var pendingWrites = 0
    private var writeFailed = false
    /// Counts every write ever enqueued, so a load can tell that one went out during its fetch
    private var writesEnqueued = 0
    /// Set when a load gave way to pending writes, so the queue loads once it drains
    private var reloadAfterWrites = false

    /// Runs server writes in submission order; a failure, or a load that gave way to the writes, resyncs once the queue drains (returns a task that ends after that drain)
    @discardableResult
    private func enqueueWrite(_ op: @escaping () async throws -> Void) -> Task<Void, Never> {
        pendingWrites += 1
        writesEnqueued += 1
        let prior = writeChain
        let write = Task {
            await prior?.value
            do {
                try await op()
            } catch {
                writeFailed = true
            }
            pendingWrites -= 1
            if pendingWrites == 0, writeFailed || reloadAfterWrites {
                writeFailed = false
                reloadAfterWrites = false
                await load()
            }
        }
        writeChain = write
        // a failure resyncs only after the last pending write, so the caller waits for every write queued after this one
        return Task {
            var awaited = write
            while true {
                await awaited.value
                guard let last = writeChain, last != awaited else { return }
                awaited = last
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
            pinned: pinned, state: existing.state, jellyfinID: existing.jellyfinID
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
            pinned: existing.pinned, state: existing.state, jellyfinID: existing.jellyfinID
        )
    }
}
