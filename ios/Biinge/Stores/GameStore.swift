import Observation

/// Holds the user's game library (want / playing / played)
@MainActor
@Observable
final class GameStore {
    private(set) var wantGames: [LibraryGame] = []
    private(set) var playingGames: [LibraryGame] = []
    private(set) var playedGames: [LibraryGame] = []
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
        async let playing = fetch(type: "playing")
        async let played = fetch(type: "played")
        let (wantResult, playingResult, playedResult) = await (want, playing, played)
        if let wantResult { wantGames = wantResult }
        if let playingResult { playingGames = playingResult }
        if let playedResult { playedGames = playedResult }
        isLoading = false
        hasLoaded = true
    }

    private func fetch(type: String) async -> [LibraryGame]? {
        try? await apiClient.games(type: type).data
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

    /// Move a game into `target`; tapping the current state removes it
    func toggle(id: Int, title: String, posterPath: String, runtime: Int, target: WatchState) async {
        let current = currentState(id: id)
        if current == target {
            removeLocal(id: id)
            enqueueWrite { [apiClient] in
                try await apiClient.deleteGame(id: id)
            }
        } else if current == nil {
            insertLocal(LibraryGame(id: id, title: title, posterPath: posterPath, pinned: false, state: target))
            enqueueWrite { [apiClient] in
                _ = try await apiClient.createGame(
                    CreateGameBody(id: id, title: title, posterPath: posterPath, runtime: runtime, state: target.rawValue)
                )
            }
        } else {
            let pinned = isPinned(id: id)
            moveLocal(id: id, to: target)
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

    private func insertLocal(_ game: LibraryGame) {
        switch game.state {
        case .want: wantGames.insert(game, at: 0)
        case .playing: playingGames.insert(game, at: 0)
        case .played: playedGames.insert(game, at: 0)
        default: break
        }
    }

    /// Move an already-tracked game to a new state segment
    private func moveLocal(id: Int, to target: WatchState) {
        guard let existing = firstMatch(id: id) else { return }
        removeLocal(id: id)
        insertLocal(LibraryGame(
            id: existing.id, title: existing.title, posterPath: existing.posterPath,
            pinned: existing.pinned, state: target
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
