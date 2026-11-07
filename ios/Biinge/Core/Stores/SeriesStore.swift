import Foundation
import Observation

/// Holds the user's series library (want / watching / watched), mirroring the RN app's series context
@MainActor
@Observable
final class SeriesStore {
    private(set) var wantSeries: [LibrarySeries] = []
    private(set) var watchingSeries: [LibrarySeries] = []
    private(set) var watchedSeries: [LibrarySeries] = []
    private(set) var isLoading = false
    /// Set only after a load in which every list arrived
    private(set) var hasLoaded = false
    /// The last load's failure, nil once a load succeeds (the lists keep what an earlier load brought)
    private(set) var loadError: (any Error)?
    /// Per-show watch progress shared by the detail screens and the grid
    private(set) var progressBySeries: [Int: WatchProgress] = [:]

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
            async let want = apiClient.series(type: "want").data
            async let watching = apiClient.series(type: "watching").data
            async let watched = apiClient.series(type: "watched").data
            let lists = try await (want, watching, watched)
            // a write that went out during the fetch may be missing from it, so the lists wait for a load after it
            guard writesEnqueued == started else {
                if pendingWrites > 0 { reloadAfterWrites = true } else { await load() }
                return
            }
            (wantSeries, watchingSeries, watchedSeries) = lists
            // the server still lists a show waiting out its Undo window, and its entry there (after any earlier write failed) is what Undo restores
            if let pending = pendingRemoval {
                if let series = firstMatch(id: pending.series.id) {
                    let list = switch series.state {
                    case .want: wantSeries
                    case .watching: watchingSeries
                    default: watchedSeries
                    }
                    pendingRemoval?.series = series
                    pendingRemoval?.index = list.firstIndex { $0.id == series.id } ?? 0
                } else {
                    // an earlier write that failed never listed it, so there is nothing to remove or bring back
                    pendingRemoval = nil
                    pending.outcome.cancel()
                }
                removeLocal(id: pending.series.id)
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
        if wantSeries.contains(where: { $0.id == id }) { return .want }
        if watchingSeries.contains(where: { $0.id == id }) { return .watching }
        if watchedSeries.contains(where: { $0.id == id }) { return .watched }
        return nil
    }

    func isPinned(id: Int) -> Bool {
        firstMatch(id: id)?.pinned ?? false
    }

    /// Locate a show in any segment without concatenating (copying) the lists
    private func firstMatch(id: Int) -> LibrarySeries? {
        wantSeries.first { $0.id == id }
            ?? watchingSeries.first { $0.id == id }
            ?? watchedSeries.first { $0.id == id }
    }

    func progress(id: Int) -> WatchProgress? {
        progressBySeries[id]
    }

    // MARK: - Mutations (optimistic: local first, serialized server write after)

    /// Each show's last add or move by its ID, ending with the write's failure (after the resync when it was the last write queued)
    private var addWrites: [Int: Task<(any Error)?, Never>] = [:]

    /// A show's entry and progress as the server last confirmed them, while its adds, moves and removals are queued
    private struct Confirmed {
        /// Nil while the server lists no entry
        var series: LibrarySeries?
        /// Where it sat in its list
        var index: Int
        var progress: WatchProgress?
        /// How many of its writes are still queued
        var writes: Int
    }

    /// Each show with an add, move or removal queued, by its ID
    private var confirmed: [Int: Confirmed] = [:]

    /// Explicit tracking updates the cached progress; unmark-all reverts to this state
    private func retrackProgress(id: Int, state: WatchState) {
        guard let cached = progressBySeries[id] else { return }
        progressBySeries[id] = WatchProgress(
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

    // MARK: - Removal with Undo

    /// The show a removal hid for its Undo window
    private struct PendingRemoval {
        var series: LibrarySeries
        /// Where it sat in its list
        var index: Int
        /// Its progress before the removal cleared it, with the outcome of any mark that ended since
        var progress: WatchProgress?
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

    /// Per-show count of episode, season and whole-show marks, so a progress read or mark response that started before a later mark on the same show gives way to it
    private(set) var episodeMarks: [Int: Int] = [:]

    /// Marks or unmarks the episode at once, then writes it in order with the library's other writes (only the show's newest mark applies the API's answer, and a failure restores the API's progress, else the progress before the mark, and throws)
    func setEpisodeWatched(
        _ watched: Bool,
        episode: EpisodeSummary,
        season: SeasonSummary,
        seasonEpisodes: [EpisodeSummary],
        details: SeriesDetails
    ) async throws {
        let id = details.id
        // the server takes the pending removal before this mark on the same show
        if pendingRemoval?.series.id == id { commitRemoval() }
        let apply = { (value: WatchProgress) in
            // a show waiting out its removal stays hidden, so the mark's outcome goes to the progress and list entry its Undo restores
            if let series = self.pendingRemoval?.series, series.id == id {
                self.pendingRemoval?.progress = value
                // the entry follows the progress as apply reflects it into the grid, where a new state lists it first
                self.pendingRemoval?.series = LibrarySeries(id: series.id, title: series.title, posterPath: series.posterPath, pinned: series.pinned, state: value.state,
                                                          episodesCount: series.episodesCount, watchedEpisodesCount: value.watchedEpisodes.count, jellyfinID: series.jellyfinID)
                if series.state != value.state { self.pendingRemoval?.index = 0 }
            } else {
                self.apply(value, id: id, title: details.title, posterPath: details.posterPath, episodesCount: details.totalEpisodesCount, pinned: details.pinned)
            }
        }
        let snapshot = progressBySeries[id]
        // before the first progress lands, the mark builds on an empty progress in the store's state
        let base = snapshot ?? WatchProgress(
            id: id, state: currentState(id: id) ?? .none, trackedState: currentState(id: id), watchedSeasons: [], watchedEpisodes: []
        )
        episodeMarks[id, default: 0] += 1
        let generation = episodeMarks[id]
        apply(base.togglingEpisode(
            id: episode.id, watched: watched, seasonId: season.id,
            seasonEpisodes: seasonEpisodes, totalSeasons: details.regularSeasonsCount, seriesStatus: details.status
        ))
        var failure: (any Error)?
        let write = enqueueWrite { [apiClient] in
            do {
                let updated: WatchProgress
                if watched {
                    let body = MarkEpisodeBody(
                        series: ProgressSeries(title: details.title, posterPath: details.posterPath, seasonsCount: details.regularSeasonsCount,
                                               episodesCount: details.totalEpisodesCount, status: details.status ?? ""),
                        season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                        episode: ProgressEpisodeMeta(title: episode.title, posterPath: episode.posterPath, runtime: episode.runtime, airDate: episode.airDate ?? "")
                    )
                    updated = try await apiClient.markEpisode(seriesId: id, seasonId: season.id, episodeId: episode.id, body)
                } else {
                    updated = try await apiClient.unmarkEpisode(seriesId: id, seasonId: season.id, episodeId: episode.id)
                }
                guard generation == self.episodeMarks[id] else { return }
                apply(updated)
            } catch {
                failure = error
                if generation == self.episodeMarks[id] {
                    if let fresh = try? await apiClient.progress(seriesId: id), generation == self.episodeMarks[id] {
                        apply(fresh)
                    } else if generation == self.episodeMarks[id] {
                        // a show with no earlier progress goes back to having none
                        if let snapshot { apply(snapshot) } else { self.progressBySeries[id] = nil }
                    }
                }
                // the queue resyncs the lists, which the optimistic mark may have moved the show between
                throw error
            }
        }
        await write.value
        if let failure { throw failure }
    }

    /// Marks or unmarks the whole season at once, then writes it in order with the library's other writes (sharing the episode marks' per-show count, so only the show's newest mark applies the API's answer; a failure restores as an episode mark's does and throws)
    func setSeasonWatched(
        _ watched: Bool,
        season: SeasonSummary,
        seasonEpisodes: [EpisodeSummary],
        details: SeriesDetails
    ) async throws {
        let id = details.id
        // the server takes the pending removal before this mark on the same show
        if pendingRemoval?.series.id == id { commitRemoval() }
        let apply = { (value: WatchProgress) in
            // a show waiting out its removal stays hidden, so the mark's outcome goes to the progress and list entry its Undo restores
            if let series = self.pendingRemoval?.series, series.id == id {
                self.pendingRemoval?.progress = value
                // the entry follows the progress as apply reflects it into the grid, where a new state lists it first
                self.pendingRemoval?.series = LibrarySeries(id: series.id, title: series.title, posterPath: series.posterPath, pinned: series.pinned, state: value.state,
                                                          episodesCount: series.episodesCount, watchedEpisodesCount: value.watchedEpisodes.count, jellyfinID: series.jellyfinID)
                if series.state != value.state { self.pendingRemoval?.index = 0 }
            } else {
                self.apply(value, id: id, title: details.title, posterPath: details.posterPath, episodesCount: details.totalEpisodesCount, pinned: details.pinned)
            }
        }
        let snapshot = progressBySeries[id]
        // before the first progress lands, the mark builds on an empty progress in the store's state
        let base = snapshot ?? WatchProgress(
            id: id, state: currentState(id: id) ?? .none, trackedState: currentState(id: id), watchedSeasons: [], watchedEpisodes: []
        )
        episodeMarks[id, default: 0] += 1
        let generation = episodeMarks[id]
        apply(base.togglingSeason(
            id: season.id, episodeIds: seasonEpisodes.map(\.id),
            watched: watched, totalSeasons: details.regularSeasonsCount, seriesStatus: details.status
        ))
        var failure: (any Error)?
        let write = enqueueWrite { [apiClient] in
            do {
                let updated: WatchProgress
                if watched {
                    let body = MarkSeasonBody(
                        series: ProgressSeries(title: details.title, posterPath: details.posterPath, seasonsCount: details.regularSeasonsCount,
                                               episodesCount: details.totalEpisodesCount, status: details.status ?? ""),
                        season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                        episodes: seasonEpisodes.map {
                            ProgressEpisode(id: $0.id, title: $0.title, posterPath: $0.posterPath, runtime: $0.runtime, airDate: $0.airDate ?? "")
                        }
                    )
                    updated = try await apiClient.markSeason(seriesId: id, seasonId: season.id, body)
                } else {
                    updated = try await apiClient.unmarkSeason(seriesId: id, seasonId: season.id)
                }
                guard generation == self.episodeMarks[id] else { return }
                apply(updated)
            } catch {
                failure = error
                if generation == self.episodeMarks[id] {
                    if let fresh = try? await apiClient.progress(seriesId: id), generation == self.episodeMarks[id] {
                        apply(fresh)
                    } else if generation == self.episodeMarks[id] {
                        // a show with no earlier progress goes back to having none
                        if let snapshot { apply(snapshot) } else { self.progressBySeries[id] = nil }
                    }
                }
                // the queue resyncs the lists, which the optimistic mark may have moved the show between
                throw error
            }
        }
        await write.value
        if let failure { throw failure }
    }

    // MARK: - Write queue

    private var writeChain: Task<Void, Never>?
    private var pendingWrites = 0
    private var writeFailed = false
    /// Counts every write ever enqueued, so a load can tell that one went out during its fetch
    private var writesEnqueued = 0
    /// Set when a load gave way to pending writes, so the queue loads once it drains
    private var reloadAfterWrites = false

    /// Runs server writes in submission order; a failure, or a load that gave way to the writes, resyncs once the queue drains
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

    private func insertLocal(_ series: LibrarySeries) {
        switch series.state {
        case .want: wantSeries.insert(series, at: 0)
        case .watching: watchingSeries.insert(series, at: 0)
        case .watched: watchedSeries.insert(series, at: 0)
        default: break
        }
    }

    /// Move an already-tracked show to a new state segment with its pin, preserving its counts
    private func moveLocal(id: Int, to target: WatchState, pinned: Bool) {
        guard let existing = firstMatch(id: id) else { return }
        removeLocal(id: id)
        insertLocal(LibrarySeries(
            id: existing.id, title: existing.title, posterPath: existing.posterPath,
            pinned: pinned, state: target,
            episodesCount: existing.episodesCount, watchedEpisodesCount: existing.watchedEpisodesCount,
            jellyfinID: existing.jellyfinID
        ))
    }

    private func setPinnedLocal(id: Int, pinned: Bool) {
        repartition(&wantSeries, id: id, pinned: pinned)
        repartition(&watchingSeries, id: id, pinned: pinned)
        repartition(&watchedSeries, id: id, pinned: pinned)
    }

    /// Flip a show's pinned flag and float pinned items to the top, matching the server's ordering
    private func repartition(_ list: inout [LibrarySeries], id: Int, pinned: Bool) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let existing = list[index]
        list[index] = LibrarySeries(
            id: existing.id, title: existing.title, posterPath: existing.posterPath,
            pinned: pinned, state: existing.state,
            episodesCount: existing.episodesCount, watchedEpisodesCount: existing.watchedEpisodesCount,
            jellyfinID: existing.jellyfinID
        )
        list = list.filter { $0.pinned } + list.filter { !$0.pinned }
    }

    private func removeLocal(id: Int) {
        wantSeries.removeAll { $0.id == id }
        watchingSeries.removeAll { $0.id == id }
        watchedSeries.removeAll { $0.id == id }
    }

    /// Caches progress for the detail screens and reflects it into the grid, inserting or removing the show as needed (not for a show waiting out its removal)
    func apply(_ value: WatchProgress, id: Int, title: String, posterPath: String, episodesCount: Int, pinned: Bool) {
        // a read from before the removal would bring back the show waiting out its Undo window
        guard pendingRemoval?.series.id != id else { return }
        progressBySeries[id] = value
        let watchedCount = value.watchedEpisodes.count
        if let current = firstMatch(id: id) {
            let updated = LibrarySeries(
                id: current.id, title: current.title, posterPath: current.posterPath,
                pinned: current.pinned, state: value.state,
                episodesCount: current.episodesCount, watchedEpisodesCount: watchedCount,
                jellyfinID: current.jellyfinID
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
                state: value.state, episodesCount: episodesCount, watchedEpisodesCount: watchedCount, jellyfinID: nil
            ))
        }
    }

    private func replaceInPlace(_ series: LibrarySeries) {
        if let i = wantSeries.firstIndex(where: { $0.id == series.id }) { wantSeries[i] = series }
        if let i = watchingSeries.firstIndex(where: { $0.id == series.id }) { watchingSeries[i] = series }
        if let i = watchedSeries.firstIndex(where: { $0.id == series.id }) { watchedSeries[i] = series }
    }

    /// Push fresher poster/title from a detail load into the cached grid item
    func refreshMetadata(id: Int, title: String, posterPath: String) {
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &wantSeries)
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &watchingSeries)
        applyMetadata(id: id, title: title, posterPath: posterPath, to: &watchedSeries)
    }

    private func applyMetadata(id: Int, title: String, posterPath: String, to list: inout [LibrarySeries]) {
        guard !posterPath.isEmpty,
              let index = list.firstIndex(where: { $0.id == id }),
              list[index].posterPath != posterPath || list[index].title != title else { return }
        let existing = list[index]
        list[index] = LibrarySeries(
            id: existing.id, title: title, posterPath: posterPath,
            pinned: existing.pinned, state: existing.state,
            episodesCount: existing.episodesCount, watchedEpisodesCount: existing.watchedEpisodesCount,
            jellyfinID: existing.jellyfinID
        )
    }
}

// MARK: - Toggling lists

extension SeriesStore {
    /// Moves the show into `target`, or removes it when it already sits there
    func toggle(
        id: Int,
        title: String,
        posterPath: String,
        seasonsCount: Int,
        episodesCount: Int,
        status: String,
        target: WatchState
    ) async {
        guard currentState(id: id) == target else {
            await move(id: id, title: title, posterPath: posterPath, seasonsCount: seasonsCount, episodesCount: episodesCount, status: status, target: target)
            return
        }
        remove(id: id)
    }

    /// Hides the show and clears its progress until its Undo window ends and the DELETE goes out (nothing happens to a show in no list)
    func remove(id: Int) {
        guard let series = firstMatch(id: id) else { return }
        // a new removal ends the Undo window of the one before it
        commitRemoval()
        let list = switch series.state {
        case .want: wantSeries
        case .watching: watchingSeries
        default: watchedSeries
        }
        let index = list.firstIndex { $0.id == id } ?? 0
        let progress = progressBySeries[id]
        removeLocal(id: id)
        // untracking deletes episode rows server-side, so open sheets drop their checkmarks too
        progressBySeries[id] = WatchProgress(id: id, state: .none, trackedState: nil, watchedSeasons: [], watchedEpisodes: [])
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
            series: series, index: index, progress: progress, number: number, session: apiClient.authManager.sessionsEnded, outcome: outcome
        )
    }

    /// Moves the show into `target` (nothing happens when it already sits there); Watched unpins it and marks every aired episode of its regular seasons watched, here and on Jellyfin
    func move(
        id: Int,
        title: String,
        posterPath: String,
        seasonsCount: Int,
        episodesCount: Int,
        status: String,
        target: WatchState
    ) async {
        // the server takes the pending removal before this write on the same show
        if pendingRemoval?.series.id == id { commitRemoval() }
        let current = currentState(id: id)
        guard current != target else { return }
        // a progress read or mark from before a move to Watched gives way to the episodes it marks
        if target == .watched { episodeMarks[id, default: 0] += 1 }
        let generation = episodeMarks[id]
        if current == nil {
            confirmed[id, default: Confirmed(series: nil, index: 0, progress: progressBySeries[id], writes: 0)].writes += 1
            let added = LibrarySeries(
                id: id, title: title, posterPath: posterPath, pinned: false,
                state: target, episodesCount: episodesCount, watchedEpisodesCount: 0,
                // the next load brings the Jellyfin item, which only the API can match
                jellyfinID: nil
            )
            insertLocal(added)
            retrackProgress(id: id, state: target)
            var failure: (any Error)?
            let write = enqueueWrite { [apiClient] in
                defer {
                    self.confirmed[id]?.writes -= 1
                    if self.confirmed[id]?.writes == 0 { self.confirmed[id] = nil }
                }
                do {
                    _ = try await apiClient.createSeries(
                        CreateSeriesBody(
                            id: id, title: title, posterPath: posterPath,
                            seasonsCount: seasonsCount, episodesCount: episodesCount,
                            status: status, state: target.rawValue
                        )
                    )
                    self.confirmed[id]?.series = added
                    self.confirmed[id]?.index = 0
                    // the optional-chained write would hold the entry while its right side reads it, so the progress goes through a local
                    let progress = self.confirmed[id]?.progress.map {
                        WatchProgress(id: $0.id, state: target, trackedState: target, watchedSeasons: $0.watchedSeasons, watchedEpisodes: $0.watchedEpisodes)
                    }
                    self.confirmed[id]?.progress = progress
                    if target == .watched { try await self.markEveryEpisode(id: id, generation: generation) }
                } catch {
                    failure = error
                    // a later write on the show carries the user's latest choice, and the last one puts back what the server holds, as the queue's resync may fail too
                    if self.confirmed[id]?.writes == 1 {
                        if self.progressBySeries[id]?.state == target { self.progressBySeries[id] = self.confirmed[id]?.progress }
                        self.restoreConfirmed(id: id)
                    }
                    throw error
                }
            }
            addWrites[id] = Task { await write.value; return failure }
        } else {
            // Want and Watching pin, so only a move to Watched unpins
            let pinned = target.isPinnable && isPinned(id: id)
            let previous = firstMatch(id: id)
            let list = switch current {
            case .want: wantSeries
            case .watching: watchingSeries
            default: watchedSeries
            }
            let index = list.firstIndex { $0.id == id } ?? 0
            confirmed[id, default: Confirmed(series: previous, index: index, progress: progressBySeries[id], writes: 0)].writes += 1
            moveLocal(id: id, to: target, pinned: pinned)
            retrackProgress(id: id, state: target)
            let moved = firstMatch(id: id)
            var failure: (any Error)?
            let write = enqueueWrite { [apiClient] in
                defer {
                    self.confirmed[id]?.writes -= 1
                    if self.confirmed[id]?.writes == 0 { self.confirmed[id] = nil }
                }
                do {
                    _ = try await apiClient.updateSeries(id: id, UpdateSeriesBody(state: target.rawValue, pinned: pinned))
                    self.confirmed[id]?.series = moved
                    self.confirmed[id]?.index = 0
                    // the optional-chained write would hold the entry while its right side reads it, so the progress goes through a local
                    let progress = self.confirmed[id]?.progress.map {
                        WatchProgress(id: $0.id, state: target, trackedState: target, watchedSeasons: $0.watchedSeasons, watchedEpisodes: $0.watchedEpisodes)
                    }
                    self.confirmed[id]?.progress = progress
                    if target == .watched { try await self.markEveryEpisode(id: id, generation: generation) }
                } catch {
                    failure = error
                    // a later write on the show carries the user's latest choice, and the last one puts back what the server holds, as the queue's resync may fail too
                    if self.confirmed[id]?.writes == 1 {
                        if self.progressBySeries[id]?.state == target { self.progressBySeries[id] = self.confirmed[id]?.progress }
                        self.restoreConfirmed(id: id)
                    }
                    throw error
                }
            }
            addWrites[id] = Task { await write.value; return failure }
        }
    }

    /// Marks every aired episode of the show's regular seasons watched in one write, which also marks them played on Jellyfin, then holds the show in Watched unpinned (the API derives Watching for a show still in production) and takes the API's progress unless a later mark or move on the show has started
    private func markEveryEpisode(id: Int, generation: Int?) async throws {
        // the body carries every season's episodes, which only the season details list
        let details = try await apiClient.seriesDetails(id: id)
        let regular = details.seasons.filter { $0.number > 0 }
        // an episode counts once it has aired, by the rule the next-episode pick uses, so a later one doesn't air already watched
        let day = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let isAired = { (episode: EpisodeSummary) in episode.airDate.map { !$0.isEmpty && $0.prefix(10) <= day } ?? false }
        let episodes = try await withThrowingTaskGroup(of: (Int, [EpisodeSummary]).self) { [apiClient] group in
            for season in regular {
                group.addTask { (season.number, try await apiClient.seasonDetails(seriesId: id, season: season.number).episodes) }
            }
            var bySeason: [Int: [EpisodeSummary]] = [:]
            for try await (number, list) in group { bySeason[number] = list }
            return bySeason
        }
        let body = MarkSeriesBody(
            series: ProgressSeries(title: details.title, posterPath: details.posterPath, seasonsCount: details.regularSeasonsCount,
                                   episodesCount: details.totalEpisodesCount, status: details.status ?? ""),
            seasons: regular.map { season in
                ProgressSeason(id: season.id, title: season.title, number: season.number, episodesCount: season.episodesCount, episodes: (episodes[season.number] ?? []).filter(isAired).map {
                    ProgressEpisode(id: $0.id, title: $0.title, posterPath: $0.posterPath, runtime: $0.runtime, airDate: $0.airDate ?? "")
                })
            }
        )
        let marked = try await apiClient.markSeries(seriesId: id, body)
        if marked.state != .watched {
            _ = try await apiClient.updateSeries(id: id, UpdateSeriesBody(state: WatchState.watched.rawValue, pinned: false))
        }
        let progress = WatchProgress(id: marked.id, state: .watched, trackedState: .watched,
                                     watchedSeasons: marked.watchedSeasons, watchedEpisodes: marked.watchedEpisodes)
        confirmed[id]?.progress = progress
        guard generation == episodeMarks[id], currentState(id: id) == .watched else { return }
        apply(progress, id: id, title: details.title, posterPath: details.posterPath, episodesCount: details.totalEpisodesCount, pinned: false)
    }

    /// Puts the show back as the server last confirmed it, or hands that entry and its progress to the removal waiting on it (drops the removal when the server lists none)
    private func restoreConfirmed(id: Int) {
        guard let entry = confirmed[id] else { return }
        if let pending = pendingRemoval, pending.series.id == id {
            if let series = entry.series {
                pendingRemoval?.series = series
                pendingRemoval?.index = entry.index
                pendingRemoval?.progress = entry.progress
            } else {
                pendingRemoval = nil
                pending.outcome.cancel()
            }
            return
        }
        removeLocal(id: id)
        guard let series = entry.series else { return }
        switch series.state {
        case .want: wantSeries.insert(series, at: min(entry.index, wantSeries.count))
        case .watching: watchingSeries.insert(series, at: min(entry.index, watchingSeries.count))
        case .watched: watchedSeries.insert(series, at: min(entry.index, watchedSeries.count))
        default: break
        }
    }

    /// Waits for the show's last add or move to sync (returns its failure once the show is back as it was, nil when it lands and when none waits)
    func addFailure(id: Int) async -> (any Error)? {
        await addWrites.removeValue(forKey: id)?.value
    }
}

// MARK: - Removal with Undo

extension SeriesStore {
    /// Puts back the show its pending removal hid, with its pin and watched episodes exactly as they were, and sends nothing (nothing happens once the removal has committed)
    func undoRemoval(id: Int) {
        guard let pending = pendingRemoval, pending.series.id == id else { return }
        pendingRemoval = nil
        pending.outcome.cancel()
        progressBySeries[id] = pending.progress
        switch pending.series.state {
        case .want: wantSeries.insert(pending.series, at: min(pending.index, wantSeries.count))
        case .watching: watchingSeries.insert(pending.series, at: min(pending.index, watchingSeries.count))
        case .watched: watchedSeries.insert(pending.series, at: min(pending.index, watchedSeries.count))
        default: break
        }
    }

    /// Whether the show's removal still waits out its Undo window (the Undo toast closes once it doesn't)
    func isRemovalPending(id: Int) -> Bool {
        pendingRemoval?.series.id == id
    }

    /// Waits for the show's pending removal to end (returns the commit's failure once its DELETE has failed, which resyncs the lists when no later write is queued, nil when it lands, on Undo and when none is pending)
    func removalFailure(id: Int) async -> (any Error)? {
        guard let pending = pendingRemoval, pending.series.id == id else { return nil }
        return await pending.outcome.value
    }

    /// Sends the pending removal's DELETE now, ending its Undo window (a failure puts the show and the progress the removal cleared back as the server holds them, unless a later write on it is queued)
    private func commitRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        let id = pending.series.id
        confirmed[id, default: Confirmed(series: pending.series, index: pending.index, progress: pending.progress, writes: 0)].writes += 1
        var failure: (any Error)?
        let write = enqueueWrite { [apiClient] in
            defer {
                self.confirmed[id]?.writes -= 1
                if self.confirmed[id]?.writes == 0 { self.confirmed[id] = nil }
            }
            // after a logout the token belongs to whoever signs in next, so the show and its episodes stay in the account that removed it
            guard pending.session == apiClient.authManager.sessionsEnded else { return }
            do {
                try await apiClient.deleteSeries(id: id, session: pending.session)
                self.confirmed[id]?.series = nil
                self.confirmed[id]?.progress = WatchProgress(id: id, state: .none, trackedState: nil, watchedSeasons: [], watchedEpisodes: [])
            } catch {
                failure = error
                // a later write on the show carries the user's latest choice, and the last one puts back what the server holds, as the queue's resync may fail too
                if self.confirmed[id]?.writes == 1 {
                    if self.progressBySeries[id]?.state == WatchState.none { self.progressBySeries[id] = self.confirmed[id]?.progress }
                    self.restoreConfirmed(id: id)
                }
                throw error
            }
        }
        removalCommits[pending.number] = Task { await write.value; return failure }
        pending.outcome.cancel()
    }
}
