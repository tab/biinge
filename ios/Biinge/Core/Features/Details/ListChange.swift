import Foundation

/// A title's add to, move between or removal from its lists, which its store's change makes: the toast confirming it, and the outcome that says why the write failed
@MainActor
struct ListChange {
    /// The toast confirming the change, with Undo on a removal where the stores wait for it (nil when the store left the list as it was)
    let toast: Toast?
    /// Ends once the write has landed or failed, giving the toast that says why it failed (nil when it landed)
    let outcome: Task<Toast?, Never>
}

extension MovieStore {
    /// Moves the movie into `target`, or removes it for nil, mirroring a change into or out of Watched to Jellyfin (nil when the movie already sits there)
    func change(
        id: Int, title: String, posterPath: String, runtime: Int, jellyfinID: String?, to target: WatchState?, connection: JellyfinConnection?
    ) async -> ListChange? {
        let old = currentState(id: id)
        guard old != target else { return nil }
        let touchesWatched = old == .watched || target == .watched
        // Home hides the movie at once, as Jellyfin may still report it unplayed
        if touchesWatched, let jellyfinID { connection?.setWatched(itemID: jellyfinID, watched: target == .watched) }
        let write = if let target {
            await move(id: id, title: title, posterPath: posterPath, runtime: runtime, target: target)
        } else {
            remove(id: id)
        }
        // the API marks the movie played on Jellyfin only when the server holds it
        let sub = target == .watched && jellyfinID != nil && connection?.isConnected == true
            ? "Also marked played on \(connection?.serverName ?? "server")" : nil
        // Apple TV's toast takes no focus, so its removal commits at once without Undo
        var undo: (@MainActor () -> Void)?
        if Toast.undoWindow > .zero { undo = { self.undoRemoval(id: id) } }
        let toast = Toast(from: old, to: currentState(id: id), kind: .movie, sub: sub, undo: undo) { self.isRemovalPending(id: id) }
        let outcome = Task { () -> Toast? in
            var failure: Toast?
            // a removal that fails to commit comes back with the resync, so the toast says why
            if await removalFailure(id: id) != nil { failure = Toast(message: "Couldn’t remove \(title)", systemImage: nil) }
            // an add or move that fails goes back as it was, so the toast says why
            if let target, await addFailure(id: id) != nil { failure = Toast(failedAdd: title, to: target) }
            // Home follows the store's state once the write (and a failure's resync) ends
            if touchesWatched, let jellyfinID {
                await write.value
                connection?.setWatched(itemID: jellyfinID, watched: currentState(id: id) == .watched)
            }
            return failure
        }
        return ListChange(toast: toast, outcome: outcome)
    }
}

extension SeriesStore {
    /// Moves the series into `target`, or removes it for nil (Watched marks every aired episode, here and on Jellyfin; `created` is what the API needs for a series in no list yet; nil when the series already sits there)
    func change(
        id: Int, title: String, posterPath: String, created: (seasonsCount: Int, episodesCount: Int, status: String),
        jellyfinID: String?, to target: WatchState?, connection: JellyfinConnection?
    ) async -> ListChange? {
        let old = currentState(id: id)
        guard old != target else { return nil }
        if let target {
            await move(
                id: id, title: title, posterPath: posterPath, seasonsCount: created.seasonsCount, episodesCount: created.episodesCount,
                status: created.status, target: target
            )
        } else {
            remove(id: id)
        }
        // Watched marks every aired episode, which reaches Jellyfin only when the server holds the series
        let sub = target == .watched && jellyfinID != nil && connection?.isConnected == true
            ? "Also marked played on \(connection?.serverName ?? "server")" : nil
        // Apple TV's toast takes no focus, so its removal commits at once without Undo
        var undo: (@MainActor () -> Void)?
        if Toast.undoWindow > .zero { undo = { self.undoRemoval(id: id) } }
        let toast = Toast(from: old, to: currentState(id: id), kind: .series, sub: sub, undo: undo) { self.isRemovalPending(id: id) }
        let outcome = Task { () -> Toast? in
            // a removal that fails to commit comes back with the resync, so the toast says why
            if await removalFailure(id: id) != nil { return Toast(message: "Couldn’t remove \(title)", systemImage: nil) }
            // an add or move that fails goes back as it was, so the toast says why
            if let target, await addFailure(id: id) != nil { return Toast(failedAdd: title, to: target) }
            return nil
        }
        return ListChange(toast: toast, outcome: outcome)
    }
}

extension GameStore {
    /// Moves the game into `target`, or removes it for nil (nil when the game already sits there)
    func change(id: Int, title: String, posterPath: String, runtime: Int, to target: WatchState?) async -> ListChange? {
        let old = currentState(id: id)
        guard old != target else { return nil }
        if let target {
            await move(id: id, title: title, posterPath: posterPath, runtime: runtime, target: target)
        } else {
            remove(id: id)
        }
        // Apple TV's toast takes no focus, so its removal commits at once without Undo
        var undo: (@MainActor () -> Void)?
        if Toast.undoWindow > .zero { undo = { self.undoRemoval(id: id) } }
        let toast = Toast(from: old, to: currentState(id: id), kind: .game, undo: undo) { self.isRemovalPending(id: id) }
        let outcome = Task { () -> Toast? in
            // a removal that fails to commit comes back with the resync, so the toast says why
            await removalFailure(id: id) != nil ? Toast(message: "Couldn’t remove \(title)", systemImage: nil) : nil
        }
        return ListChange(toast: toast, outcome: outcome)
    }
}
