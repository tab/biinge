import Observation

/// Holds the user's game library (want / playing / played)
@MainActor
@Observable
final class GameStore {
    private(set) var wantGames: [LibraryGame] = []
    private(set) var playingGames: [LibraryGame] = []
    private(set) var playedGames: [LibraryGame] = []
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
            async let want = apiClient.games(type: "want").data
            async let playing = apiClient.games(type: "playing").data
            async let played = apiClient.games(type: "played").data
            let lists = try await (want, playing, played)
            // a write that went out during the fetch may be missing from it, so the lists wait for a load after it
            guard writesEnqueued == started else {
                if pendingWrites > 0 { reloadAfterWrites = true } else { await load() }
                return
            }
            (wantGames, playingGames, playedGames) = lists
            // the server still lists a game waiting out its Undo window, and its entry there (after any earlier write failed) is what Undo restores
            if let pending = pendingRemoval {
                if let game = firstMatch(id: pending.game.id) {
                    let list = switch game.state {
                    case .want: wantGames
                    case .playing: playingGames
                    default: playedGames
                    }
                    pendingRemoval?.game = game
                    pendingRemoval?.index = list.firstIndex { $0.id == game.id } ?? 0
                } else {
                    // an earlier write that failed never listed it, so there is nothing to remove or bring back
                    pendingRemoval = nil
                    pending.outcome.cancel()
                }
                removeLocal(id: pending.game.id)
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
        if wantGames.contains(where: { $0.id == id }) { return .want }
        if playingGames.contains(where: { $0.id == id }) { return .playing }
        if playedGames.contains(where: { $0.id == id }) { return .played }
        return nil
    }

    func isPinned(id: Int) -> Bool {
        firstMatch(id: id)?.pinned ?? false
    }

    /// Locate a game in any segment without concatenating (copying) the lists
    private func firstMatch(id: Int) -> LibraryGame? {
        wantGames.first { $0.id == id }
            ?? playingGames.first { $0.id == id }
            ?? playedGames.first { $0.id == id }
    }

    // MARK: - Mutations (optimistic: local first, serialized server write after)

    /// Moves the game into `target`, or removes it when it already sits there
    func toggle(id: Int, title: String, posterPath: String, runtime: Int, target: WatchState) async {
        guard currentState(id: id) == target else {
            await move(id: id, title: title, posterPath: posterPath, runtime: runtime, target: target)
            return
        }
        remove(id: id)
    }

    /// Hides the game until its Undo window ends and the DELETE goes out (nothing happens to a game in no list)
    func remove(id: Int) {
        guard let game = firstMatch(id: id) else { return }
        // a new removal ends the Undo window of the one before it
        commitRemoval()
        let list = switch game.state {
        case .want: wantGames
        case .playing: playingGames
        default: playedGames
        }
        let index = list.firstIndex { $0.id == id } ?? 0
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
            game: game, index: index, number: number, session: apiClient.authManager.sessionsEnded, outcome: outcome
        )
    }

    /// Moves the game into `target`, unpinned when `target` is Played (nothing happens when it already sits there)
    func move(id: Int, title: String, posterPath: String, runtime: Int, target: WatchState) async {
        // the server takes the pending removal before this write on the same game
        if pendingRemoval?.game.id == id { commitRemoval() }
        let current = currentState(id: id)
        guard current != target else { return }
        if current == nil {
            insertLocal(LibraryGame(id: id, title: title, posterPath: posterPath, pinned: false, state: target))
            enqueueWrite { [apiClient] in
                _ = try await apiClient.createGame(
                    CreateGameBody(id: id, title: title, posterPath: posterPath, runtime: runtime, state: target.rawValue)
                )
            }
        } else {
            // Want and Playing pin, so only a move to Played unpins
            let pinned = target.isPinnable && isPinned(id: id)
            moveLocal(id: id, to: target, pinned: pinned)
            enqueueWrite { [apiClient] in
                _ = try await apiClient.updateGame(id: id, UpdateGameBody(state: target.rawValue, pinned: pinned))
            }
        }
    }

    func setPinned(id: Int, pinned: Bool) async {
        guard let current = currentState(id: id) else { return }
        setPinnedLocal(id: id, pinned: pinned)
        enqueueWrite { [apiClient] in
            _ = try await apiClient.updateGame(id: id, UpdateGameBody(state: current.rawValue, pinned: pinned))
        }
    }

    // MARK: - Removal with Undo

    /// The game a removal hid for its Undo window
    private struct PendingRemoval {
        var game: LibraryGame
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
    /// Each committed removal's DELETE by its number, ending with its failure (after the resync when it was the last write queued)
    private var removalCommits: [Int: Task<(any Error)?, Never>] = [:]

    /// Puts back the game its pending removal hid, exactly as it was, and sends nothing (nothing happens once the removal has committed)
    func undoRemoval(id: Int) {
        guard let pending = pendingRemoval, pending.game.id == id else { return }
        pendingRemoval = nil
        pending.outcome.cancel()
        switch pending.game.state {
        case .want: wantGames.insert(pending.game, at: min(pending.index, wantGames.count))
        case .playing: playingGames.insert(pending.game, at: min(pending.index, playingGames.count))
        case .played: playedGames.insert(pending.game, at: min(pending.index, playedGames.count))
        default: break
        }
    }

    /// Whether the game's removal still waits out its Undo window (the Undo toast closes once it doesn't)
    func isRemovalPending(id: Int) -> Bool {
        pendingRemoval?.game.id == id
    }

    /// Waits for the game's pending removal to end (returns the commit's failure once its DELETE has failed, which resyncs the lists when no later write is queued, nil when it lands, on Undo and when none is pending)
    func removalFailure(id: Int) async -> (any Error)? {
        guard let pending = pendingRemoval, pending.game.id == id else { return nil }
        return await pending.outcome.value
    }

    /// Sends the pending removal's DELETE now, ending its Undo window (a failure puts the game back, unless a later write has listed it again)
    private func commitRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        let id = pending.game.id
        var failure: (any Error)?
        let write = enqueueWrite { [apiClient] in
            // after a logout the token belongs to whoever signs in next, so the game stays listed in the account that removed it
            guard pending.session == apiClient.authManager.sessionsEnded else { return }
            do {
                try await apiClient.deleteGame(id: id, session: pending.session)
            } catch {
                failure = error
                // the game comes back here, as the queue's resync may fail too
                if self.currentState(id: id) == nil, self.pendingRemoval?.game.id != id {
                    switch pending.game.state {
                    case .want: self.wantGames.insert(pending.game, at: min(pending.index, self.wantGames.count))
                    case .playing: self.playingGames.insert(pending.game, at: min(pending.index, self.playingGames.count))
                    case .played: self.playedGames.insert(pending.game, at: min(pending.index, self.playedGames.count))
                    default: break
                    }
                }
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

    /// Runs server writes in submission order; a failure, or a load that gave way to the writes, resyncs once the queue drains (returns the write's task, which ends after that resync when it was the last)
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
        return write
    }

    private func insertLocal(_ game: LibraryGame) {
        switch game.state {
        case .want: wantGames.insert(game, at: 0)
        case .playing: playingGames.insert(game, at: 0)
        case .played: playedGames.insert(game, at: 0)
        default: break
        }
    }

    /// Move an already-tracked game to a new state segment with its pin
    private func moveLocal(id: Int, to target: WatchState, pinned: Bool) {
        guard let existing = firstMatch(id: id) else { return }
        removeLocal(id: id)
        insertLocal(LibraryGame(
            id: existing.id, title: existing.title, posterPath: existing.posterPath,
            pinned: pinned, state: target
        ))
    }

    private func setPinnedLocal(id: Int, pinned: Bool) {
        repartition(&wantGames, id: id, pinned: pinned)
        repartition(&playingGames, id: id, pinned: pinned)
        repartition(&playedGames, id: id, pinned: pinned)
    }

    /// Flip a game's pinned flag and float pinned items to the top, matching the server's ordering
    private func repartition(_ list: inout [LibraryGame], id: Int, pinned: Bool) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let existing = list[index]
        list[index] = LibraryGame(
            id: existing.id, title: existing.title, posterPath: existing.posterPath,
            pinned: pinned, state: existing.state
        )
        list = list.filter { $0.pinned } + list.filter { !$0.pinned }
    }

    private func removeLocal(id: Int) {
        wantGames.removeAll { $0.id == id }
        playingGames.removeAll { $0.id == id }
        playedGames.removeAll { $0.id == id }
    }

    /// Push fresher cover/title from a detail load into the cached grid item
    func refreshMetadata(id: Int, title: String, posterPath: String) {
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &wantGames)
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &playingGames)
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &playedGames)
    }

    private func applyMetadata(id: Int, title: String, posterPath: String, to list: inout [LibraryGame]) {
        guard !posterPath.isEmpty,
              let index = list.firstIndex(where: { $0.id == id }),
              list[index].posterPath != posterPath || list[index].title != title else { return }
        let existing = list[index]
        list[index] = LibraryGame(
            id: existing.id, title: title, posterPath: posterPath,
            pinned: existing.pinned, state: existing.state
        )
    }
}
