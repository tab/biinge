import Foundation

/// A details screen's kind of title, which sets its lists and its next step
enum DetailKind {
    case movie
    case series
    case game
}

extension WatchState {
    /// Whether a title in this list can be pinned to Up Next (Want, Watching and Playing; moving to any other list unpins)
    var isPinnable: Bool {
        self == .want || self == .watching || self == .playing
    }
}

/// One list of the details list menu, with its one-line description
struct DetailList: Equatable {
    let state: WatchState
    let name: String
    let systemImage: String
    /// The menu row's description (a list that writes to Jellyfin names the server)
    let summary: String

    /// The kind's lists in menu order, naming the Jellyfin server in the descriptions that write to it
    static func lists(_ kind: DetailKind, server: String) -> [DetailList] {
        switch kind {
        case .movie:
            [
                DetailList(state: .want, name: "Want to Watch", systemImage: "bookmark.fill", summary: "Saved for later."),
                DetailList(state: .watched, name: "Watched", systemImage: "checkmark.circle.fill", summary: "Also marks it played on \(server)."),
            ]
        case .series:
            [
                DetailList(state: .want, name: "Want to Watch", systemImage: "bookmark.fill", summary: "Saved for later."),
                DetailList(state: .watching, name: "Watching", systemImage: "circle.lefthalf.filled", summary: "Biinge follows your next episode."),
                DetailList(state: .watched, name: "Watched", systemImage: "checkmark.circle.fill",
                           summary: "Marks every episode watched, here and on \(server)."),
            ]
        case .game:
            [
                DetailList(state: .want, name: "Want to Play", systemImage: "bookmark.fill", summary: "Saved for later."),
                DetailList(state: .playing, name: "Playing", systemImage: "gamecontroller.fill", summary: "What you’re playing now."),
                DetailList(state: .played, name: "Played", systemImage: "checkmark.circle.fill", summary: "Finished, or done with it. Unpins it."),
            ]
        }
    }
}

/// The action row's list pill: the title's list and pin, else Add to List (it opens the list menu and changes nothing itself)
struct DetailListPill: Equatable {
    let label: String
    let systemImage: String
    let isPinned: Bool

    init(_ kind: DetailKind, state: WatchState?, isPinned: Bool) {
        guard let list = DetailList.lists(kind, server: "").first(where: { $0.state == state }) else {
            self.label = "Add to List"
            self.systemImage = "plus"
            self.isPinned = false
            return
        }
        self.label = list.name
        self.systemImage = list.systemImage
        self.isPinned = isPinned
    }
}

/// The action row's white pill: the play when the title can play here, else the title's next list
struct DetailPrimary: Equatable {
    /// What a tap on the pill does
    enum Action: Equatable {
        /// Plays the Jellyfin item with this ID
        case play(String)
        /// Nothing while the server is unreachable (the pill shows the play's label disabled)
        case unreachable
        /// Moves the title to this list
        case move(WatchState)
    }

    let label: String
    /// The time left after a movie's Resume ("1h 12m left"), which a narrow row leaves off
    let detail: String?
    let systemImage: String?
    let action: Action

    /// The label with its detail ("Resume · 1h 12m left")
    var title: String {
        detail.map { "\(label) · \($0)" } ?? label
    }

    /// A movie's pill: Resume, Play Again or Play when it can play, else Add to Want to Watch while it sits in no list (positions and runtimes in Jellyfin ticks; nil when there's no next step)
    static func movie(play: DetailsPlay, state: WatchState?, position: Int, runtime: Int, playedOnServer: Bool) -> DetailPrimary? {
        guard play != .connect, play != .notOnServer else {
            return state == nil ? DetailPrimary(label: "Add to Want to Watch", detail: nil, systemImage: nil, action: .move(.want)) : nil
        }
        let action: Action = if case .play(let jellyfinID) = play { .play(jellyfinID) } else { .unreachable }
        if position > 0 {
            return DetailPrimary(label: "Resume", detail: "\(duration(ticks: max(runtime - position, 0))) left", systemImage: "play.fill", action: action)
        }
        if state == .watched || playedOnServer {
            return DetailPrimary(label: "Play Again", detail: nil, systemImage: "arrow.counterclockwise", action: action)
        }
        return DetailPrimary(label: "Play", detail: nil, systemImage: "play.fill", action: action)
    }

    /// A series' pill for the episode its details offer: Resume, Play Again (watched or played, and caught up, so the offer is the opener again) or Play when it can play, else Add to Want to Watch while it sits in no list (`play` is the offered episode's, and nil `episode` while none is offered)
    static func series(
        play: DetailsPlay, state: WatchState?, episode: (season: Int, number: Int)?, position: Int, caughtUp: Bool, playedOnServer: Bool
    ) -> DetailPrimary? {
        guard let episode, play != .connect, play != .notOnServer else {
            return state == nil ? DetailPrimary(label: "Add to Want to Watch", detail: nil, systemImage: nil, action: .move(.want)) : nil
        }
        let action: Action = if case .play(let jellyfinID) = play { .play(jellyfinID) } else { .unreachable }
        let code = "S\(episode.season) · E\(episode.number)"
        if position > 0 {
            return DetailPrimary(label: "Resume \(code)", detail: nil, systemImage: "play.fill", action: action)
        }
        if caughtUp, state == .watched || playedOnServer {
            return DetailPrimary(label: "Play Again · \(code)", detail: nil, systemImage: "arrow.counterclockwise", action: action)
        }
        return DetailPrimary(label: "Play \(code)", detail: nil, systemImage: "play.fill", action: action)
    }

    /// A game's pill, one list forward: Add to Want to Play, Mark as Playing once released, Mark as Played (nil for Played, and for Want before release)
    static func game(state: WatchState?, isReleased: Bool) -> DetailPrimary? {
        switch state {
        case nil: DetailPrimary(label: "Add to Want to Play", detail: nil, systemImage: nil, action: .move(.want))
        case .want? where isReleased: DetailPrimary(label: "Mark as Playing", detail: nil, systemImage: "gamecontroller.fill", action: .move(.playing))
        case .playing?: DetailPrimary(label: "Mark as Played", detail: nil, systemImage: "checkmark", action: .move(.played))
        default: nil
        }
    }
}

extension GameDetails {
    /// Whether the game is out, which offers Mark as Playing: the status where it decides, otherwise the release date (the API sends no status for a game with no date, and IGDB's other statuses say nothing about release)
    func isReleased(now: Date = .now) -> Bool {
        switch status {
        case "Released", "Early Access", "Delisted": true
        case "Upcoming", "Cancelled": false
        default:
            // release dates are calendar days, compared as text with today's local day
            releaseDate.map { !$0.isEmpty && $0.prefix(10) <= now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()) } ?? false
        }
    }

    /// The note under the actions of a game still to come, with its release date or its lack of one (nil for a game that's out, a cancelled one, and one tracked as Playing or Played, which is out whatever IGDB says)
    func releaseNote(state: WatchState?, now: Date = .now) -> String? {
        guard !isReleased(now: now), status != "Cancelled", state == nil || state == .want else { return nil }
        let release = releaseDate.flatMap { try? Date(String($0.prefix(10)), strategy: .iso8601.year().month().day()) }
        // the date holds no time, so it formats in UTC to keep its day
        return release.map { "Not out yet. Out \($0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)))." } ?? "Not out yet. No release date."
    }
}
