import Foundation

/// A short confirmation of a change that `toast(_:)` shows (a new toast replaces the one showing)
struct Toast: Equatable {
    /// Tells a replacement from the toast it replaces, even when both say the same
    let id = UUID()
    let message: String
    /// The green symbol before the message
    let systemImage: String?
    /// A quieter second line under the message, such as a side effect on Jellyfin
    var sub: String?
    /// Puts back what a removal took away, which shows the Undo pill and keeps the toast up for the store's Undo window
    var undo: (@MainActor () -> Void)?
    /// Whether the store still holds the removal, read as the toast draws so it closes the moment the removal commits
    var canUndo: (@MainActor () -> Bool)?

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }

    #if os(tvOS)
    // shortcut: the Apple TV toast takes no focus, so a removal there commits at once; give it a focusable Undo to open the window
    /// How long a removal waits for Undo before the stores send it
    static let undoWindow: Duration = .zero
    #else
    /// How long a removal waits for Undo before the stores send it
    static let undoWindow: Duration = .seconds(4)
    #endif
}

extension Toast {
    /// The toast confirming a title's add to, move between or removal from the kind's lists, with Undo on a removal while `canUndo` holds (nil when the list didn't change)
    init?(
        from old: WatchState?, to new: WatchState?, kind: DetailKind, sub: String? = nil,
        undo: (@MainActor () -> Void)? = nil, canUndo: (@MainActor () -> Bool)? = nil
    ) {
        guard old != new else { return nil }
        let lists = DetailList.lists(kind, server: "")
        if let list = lists.first(where: { $0.state == new }) {
            self.init(message: "\(old == nil ? "Added" : "Moved") to \(list.name)", systemImage: list.systemImage, sub: sub)
        } else if let list = lists.first(where: { $0.state == old }) {
            self.init(message: "Removed from \(list.name)", systemImage: "minus.circle.fill", sub: sub, undo: undo, canUndo: canUndo)
        } else {
            return nil
        }
    }

    /// The toast confirming a pin to Up Next or its removal
    init(pinned: Bool) {
        self.init(message: pinned ? "Pinned to Up Next" : "Unpinned from Up Next", systemImage: "pin.fill")
    }

    /// The toast saying a title's add or move to `target` didn't reach the server, so the title went back as it was
    init(failedAdd title: String, to target: WatchState) {
        let list = switch target {
        case .want: "Want to Watch"
        case .watching: "Watching"
        default: "Watched"
        }
        self.init(message: "Couldn’t add \(title) to \(list)", systemImage: nil)
    }

    /// The toast confirming an episode's watched mark
    init(episodeWatched watched: Bool) {
        self.init(message: watched ? "Marked watched" : "Marked unwatched", systemImage: watched ? "checkmark.circle.fill" : nil)
    }
}
