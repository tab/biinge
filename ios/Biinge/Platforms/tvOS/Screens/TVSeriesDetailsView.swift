import JellyfinAPI
import SwiftUI

/// Apple TV series details from biinge: poster, title, meta, the watched count, the next step, list and ••• pills with their menus, the overview and facts, then the season tabs and episode rows, Cast & Crew, Recommendations and More in Your Library
struct TVSeriesDetailsView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// The series' TMDB ID
    let id: Int
    /// The Jellyfin poster of the tile the details opened from, shown in place of the TMDB poster (nil for the TMDB poster)
    let libraryPoster: URL?

    /// Where focus sits: the next step's pill, the list pill, a season tab or an episode row by its TMDB ID
    private enum Focus: Hashable {
        case primary
        case list
        case season(Int)
        case episode(Int)
    }

    /// The series, its seasons and the next episode, nil until the first load has the environment's store
    @State private var model: SeriesDetailsState?
    /// The list a click would remove the series from, which deletes its episode marks, nil when no confirmation shows
    @State private var untrack: WatchState?
    /// The confirmation of the last list change, pin or season mark, nil when none shows
    @State private var toast: Toast?
    /// The list menu or More while one shows
    @State private var menu: DetailMenu?
    /// Set while the page skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    /// Set while the episode list's skeleton holds its 500 ms
    @State private var isEpisodesSkeletonHeld = false
    @Environment(SeriesStore.self) private var store
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Focus?

    var body: some View {
        let details = model?.details
        let ended = connection.playbackEnded
        Group {
            if !isSkeletonHeld, let model, let details {
                // the page fades in as the skeleton leaves, and the swap animates nothing else
                page(model, details)
                    .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else if !isSkeletonHeld, let model, let failure = model.failure {
                Message(icon: "icloud.slash", title: "Can’t reach Biinge", text: failure, action: "Try Again") {
                    Task { await model.load() }
                }
                .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else {
                skeleton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background {
            ZStack {
                Color.biingeBackground
                // the backdrop arrives with the page, after a shown skeleton's hold
                if !isSkeletonHeld, let details {
                    TVBackdropArt(url: Config.tmdbImageURL(path: details.posterPath, size: "w780"))
                        .backdropFade()
                }
                LinearGradient(
                    stops: [.init(color: Color.biingeBackground.opacity(0.7), location: 0), .init(color: Color.biingeBackground.opacity(0.1), location: 0.75)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    stops: [.init(color: Color.biingeBackground.opacity(0), location: 0.3), .init(color: Color.biingeBackground, location: 0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .alert(
            "Couldn’t change Watched",
            isPresented: Binding(get: { model?.watchedFailure != nil }, set: { if !$0 { model?.watchedFailure = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(model?.watchedFailure ?? "")
        }
        .confirmationDialog(
            "Remove \(details?.title ?? "this show") from \(untrack == .want ? "Want to Watch" : untrack == .watching ? "Watching" : "Watched")?",
            isPresented: Binding(get: { untrack != nil }, set: { if !$0 { untrack = nil } }),
            presenting: untrack
        ) { _ in
            Button("Remove", role: .destructive) {
                if let details { change(details, to: nil) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Biinge also deletes every episode you marked watched in this show.")
        }
        .tvDetailMenu($menu, poster: Config.tmdbImageURL(path: details?.posterPath ?? "", size: "w780"), title: details?.title ?? "", toast: $toast) { shown in
            guard let model, let details else { return [] }
            return shown == .list ? listRows(details) : moreRows(model, details)
        }
        .toast($toast)
        // the API matches the Jellyfin items for the connected account, so a new connection fetches the details and seasons again
        .task(id: connection.userID) {
            let model = model ?? SeriesDetailsState(apiClient: apiClient, store: store, connection: connection, seriesID: id)
            self.model = model
            let opens = model.season == nil
            await model.load()
            // focus lands on the next episode's button once it shows, so the header stays on screen
            if opens, model.season != nil, model.nextEpisode?.jellyfinID != nil, connection.isConnected, model.details?.jellyfinID != nil {
                focus = .primary
            }
        }
        // a mark that finishes a season moves the next episode into a season that may not have loaded yet
        .task(id: model?.next.season) {
            if let model, let number = model.next.season { await model.seasons.load(number) }
        }
        // a caught-up show still airing replays its opener, so the last regular season, which holds the next air date, loads for the "airs" note
        .task(id: model?.isCaughtUp) {
            let isAiring = ["Returning Series", "In Production", "Planned", "Pilot"].contains(details?.status ?? "")
            guard let model, model.isCaughtUp, isAiring, let last = details?.seasons.filter({ $0.number > 0 }).map(\.number).max() else { return }
            await model.seasons.load(last)
        }
        // the Jellyfin reads, again after a connect and once a stopped play's report has gone out
        .task(id: "\(model?.nextEpisode?.jellyfinID ?? "")-\(connection.isConnected)-\(ended)") { await model?.loadNextItem() }
        .task(id: "\(details?.jellyfinID ?? "")-\(connection.isConnected)-\(ended)") { await model?.loadSeriesItem() }
        // a load starts the seasons over, so their shares load again for the new ones
        .task(id: "\(details?.jellyfinID ?? "")-\(model?.season ?? -1)-\(connection.isConnected)-\(ended)-\(model.map { ObjectIdentifier($0.seasons).hashValue } ?? 0)") {
            await model?.loadShares()
        }
    }

    private func page(_ model: SeriesDetailsState, _ details: SeriesDetails) -> some View {
        let title = details.title
        let watched = model.progress?.watchedEpisodes.count ?? 0
        let total = details.totalEpisodesCount
        let seasons = details.regularSeasonsCount
        let meta = [DetailFact.release(details.releaseDate) ?? "", seasons == 1 ? "1 Season" : "\(seasons) Seasons", details.genres.prefix(3).joined(separator: ", ")]

        return ScrollView {
            VStack(alignment: .leading, spacing: 72) {
                VStack(alignment: .leading, spacing: 48) {
                    HStack(alignment: .bottom, spacing: 72) {
                        // the slot stays clear until the poster grows in, so the background shows through
                        PosterImage(title: title, cornerRadius: 0, poster: libraryPoster ?? Config.tmdbImageURL(path: details.posterPath, size: "w780"),
                                    frame: CGSize(width: 340, height: 510), titleFont: .system(size: 26), titlePadding: 20)
                            .environment(\.imageLoadsClear, true)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.biingeText.opacity(0.1), lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                if store.isPinned(id: id) { PinBadge() }
                            }
                            .detailWatchedBadge(store.currentState(id: id) == .watched)
                            .shadow(color: Color.biingeShadow.opacity(0.6), radius: 45, y: 40)
                        VStack(alignment: .leading, spacing: 20) {
                            Text("TV Show")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(Color.biingeText.opacity(0.75))
                            Text(title)
                                .font(.system(size: title.count > 28 ? 84 : title.count > 14 ? 104 : 128, weight: .bold))
                                .tracking((title.count > 28 ? 84 : title.count > 14 ? 104 : 128) * -0.035)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                            HStack(spacing: 22) {
                                Text(meta.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .foregroundStyle(Color.biingeText.opacity(0.82))
                                if let rating = details.rating, rating > 0 {
                                    HStack(spacing: 6) {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(Color.biingePrimary)
                                        Text(rating, format: .number.precision(.fractionLength(1)))
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .font(.system(size: 29))
                            if total > 0 {
                                HStack(spacing: 20) {
                                    Capsule()
                                        .fill(Color.biingeText.opacity(0.22))
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(Color.biingeText).frame(width: 420 * min(Double(watched) / Double(total), 1))
                                        }
                                        .frame(width: 420, height: 8)
                                    Text("\(watched) of \(total) episodes watched")
                                        .font(.system(size: 26))
                                        .foregroundStyle(Color.biingeText.opacity(0.75))
                                }
                            }
                            actions(model, details)
                                .padding(.top, 8)
                            Text(details.overview)
                                .font(.system(size: 30))
                                .lineSpacing(7)
                                .lineLimit(2)
                                .foregroundStyle(Color.biingeText.opacity(0.82))
                                .frame(maxWidth: 1080, alignment: .leading)
                            TVDetailFacts(facts: DetailFact.series(details, state: store.currentState(id: id)))
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .focusSection()
                    if !details.seasons.isEmpty {
                        seasonList(model, details)
                    }
                }
                .padding(.horizontal, 96)
                // the first episode row stays on the first screen, so focus landing on it doesn't scroll the header away
                .padding(.top, 80)
                TVDetailsRows(
                    connection: connection, itemID: details.jellyfinID, credits: details.credits,
                    recommendations: TVRecommendationsRow(
                        items: details.recommendations, state: store.currentState(id:),
                        poster: { Config.tmdbImageURL(path: $0.posterPath, size: "w500") },
                        route: { .title(.series($0.id)) }
                    )
                )
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea()
        // the page appears before the next episode's season loads, so the first pill is also the focus engine's default
        .defaultFocus($focus, .primary)
    }

    /// The season tabs with the shown season's count and length, then its episode rows
    private func seasonList(_ model: SeriesDetailsState, _ details: SeriesDetails) -> some View {
        let season = model.season
        let seasons = model.seasons
        let shown = details.seasons.first { $0.number == season }
        let rows = season.flatMap { seasons.episodes[$0] }
        let seasonMinutes = rows?.reduce(0) { $0 + $1.runtime } ?? 0
        return VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 24) {
                // a long series has more seasons than the screen is wide, so the row scrolls to the focused one
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(details.seasons) { item in
                            Button {
                                model.season = item.number
                                Task { await seasons.load(item.number) }
                            } label: {
                                Text(item.number == 0 ? "Specials" : "Season \(item.number)")
                            }
                            .buttonStyle(SeasonTabStyle(isSelected: item.number == season))
                            .focused($focus, equals: .season(item.number))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // the focused tab's lift would otherwise clip at the row's edges
                .scrollClipDisabled()
                .focusSection()
                if let rows {
                    Text("\(rows.count == 1 ? "1 episode" : "\(rows.count) episodes") · \(duration(ticks: seasonMinutes * 600_000_000))")
                        .font(.system(size: 25))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                }
            }
            if !isEpisodesSkeletonHeld, let rows, let shown {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, episode in
                        let isWatched = model.progress.map { $0.watchedEpisodes.contains(episode.id) } ?? episode.watched
                        NavigationLink(value: TVRoute.episode(series: id, season: shown.number, episode: episode.number)) {
                            TVEpisodeRow(connection: connection, episode: episode, isWatched: isWatched, share: seasons.share(episode))
                        }
                        .buttonStyle(EpisodeRowStyle())
                        .focused($focus, equals: .episode(episode.id))
                        // a long press marks the episode, as the Mac row's Watched button does
                        .contextMenu {
                            Button(isWatched ? "Mark as Unwatched" : "Mark as Watched") {
                                Task { await model.setWatched(!isWatched, episode: episode, season: shown, seasonEpisodes: rows) }
                            }
                        }
                        .rowFade(at: index)
                    }
                }
                .focusSection()
            } else if !isEpisodesSkeletonHeld, let number = season, let failure = seasons.failures[number] {
                HStack(spacing: 32) {
                    Label("Couldn’t load this season. \(failure)", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 29))
                        .foregroundStyle(Color(rgb: 0xFF8A8D))
                    Button {
                        Task { await seasons.load(number) }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle())
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .focusSection()
            } else {
                episodesSkeleton
            }
        }
    }

    /// The next step's pill (the offered episode's play, else Add to Want to Watch), the list pill and •••, then the note on why Play isn't here, what airs next or that Jellyfin played the series unmarked
    @ViewBuilder
    private func actions(_ model: SeriesDetailsState, _ details: SeriesDetails) -> some View {
        let next = model.next
        let state = store.currentState(id: id)
        let isPlayed = model.seriesItem?.userData?.isPlayed == true
        // no pill until the pick settles, so Add to Want to Watch doesn't flash before the play
        let primary: DetailPrimary? = if case .loading = next {
            nil
        } else {
            DetailPrimary.series(
                play: model.nextPlay, state: state, episode: next.season.flatMap { season in model.nextEpisode.map { (season: season, number: $0.number) } },
                position: model.nextPosition, caughtUp: model.isCaughtUp, playedOnServer: isPlayed
            )
        }
        let pill = DetailListPill(.series, state: state, isPinned: store.isPinned(id: id))
        let server = connection.serverName ?? "server"
        HStack(spacing: 22) {
            if let primary {
                Button {
                    switch primary.action {
                    case .play(let jellyfinID):
                        // a fresh item, so the play resumes from the position Jellyfin holds now
                        attemptPlay {
                            guard let service = connection.service else { return }
                            await connection.play(try await service.item(id: jellyfinID))
                        }
                    case .unreachable:
                        toast = Toast(message: "Can’t reach \(server)", systemImage: nil)
                    case .move(let target):
                        change(details, to: target)
                    }
                } label: {
                    Label(primary.title, systemImage: primary.systemImage ?? "bookmark")
                }
                .buttonStyle(PillButtonStyle(isPrimary: true, isDisabled: primary.action == .unreachable))
                .focused($focus, equals: .primary)
                // the add folds the pill away as the list pill takes the list's name
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
            Button { menu = .list } label: {
                ListPillLabel(kind: .series, pill: pill, isUnlisted: state == nil)
            }
            .buttonStyle(PillButtonStyle(isMenu: true, isPinned: pill.isPinned))
            // the list pill keeps its own focus value, so the load's move to the play isn't a no-op when the list pill took the first focus
            .focused($focus, equals: .list)
            if !moreRows(model, details).isEmpty {
                Button { menu = .more } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .buttonStyle(PillButtonStyle(isIconOnly: true))
            }
        }
        .animation(MotionCurve.exit.animation(MotionDuration.quick), value: primary == nil)
        // the next episode waits on a season other than the shown one, so its error shows here (the shown season keeps its own)
        if let failed = next.failedSeason(failures: model.seasons.failures, shown: model.season), let failure = model.seasons.failures[failed] {
            HStack(spacing: 32) {
                Label("Couldn’t load season \(failed). \(failure)", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(rgb: 0xFF8A8D))
                Button {
                    Task { await model.seasons.load(failed) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle())
            }
            .focusSection()
        }
        // Jellyfin's played mark doesn't reach biinge by itself (episode counts, since an airing series never reaches Watched)
        let playedUnwatched = isPlayed && state != .watched && model.progress?.watchedEpisodes.count ?? 0 < details.totalEpisodesCount
        ForEach([model.episodeNote, PlayNote(play: model.seriesPlay, server: connection.serverName, playedUnwatched: playedUnwatched)].compactMap { $0 }, id: \.kind) { note in
            Label {
                Text(note.text)
            } icon: {
                switch note.kind {
                case .unreachable: Image(systemName: note.systemImage).foregroundStyle(Color.biingeError)
                case .connect, .seasonNotOnServer, .airs: Image(systemName: note.systemImage).foregroundStyle(Color.biingeTextSecondary)
                case .notOnServer, .playedUnwatched: Image(systemName: note.systemImage)
                }
            }
            .font(.system(size: 26))
            .foregroundStyle(Color.biingeText.opacity(0.6))
        }
    }
}

extension TVSeriesDetailsView {
    /// The list menu's rows: Want to Watch, Watching and Watched, then Pin to Up Next and Remove (which asks first, as it deletes the episode marks)
    private func listRows(_ details: SeriesDetails) -> [MenuRow] {
        let state = store.currentState(id: id)
        return MenuRow.lists(
            .series, server: connection.serverName ?? "server", state: state, isPinned: store.isPinned(id: id),
            move: { change(details, to: $0) },
            pin: { pinned in
                Task { await store.setPinned(id: id, pinned: pinned) }
                toast = Toast(pinned: pinned)
            },
            remove: { untrack = state }
        )
    }

    /// More's rows: Start Over for the offered episode while Jellyfin holds its position, and Mark Season Watched for the offered episode's season while the server holds the series (empty otherwise, which hides •••)
    private func moreRows(_ model: SeriesDetailsState, _ details: SeriesDetails) -> [MenuRow] {
        var rows: [MenuRow] = []
        let server = connection.serverName ?? "server"
        if case .play = model.nextPlay, model.nextPosition > 0, let nextItem = model.nextItem, let number = model.next.season, let episode = model.nextEpisode {
            rows.append(MenuRow(label: "Start S\(number) · E\(episode.number) Over", systemImage: "arrow.counterclockwise", summary: "From 0:00") {
                Task { await connection.play(nextItem, fromStart: true) }
            })
        }
        if case .play = model.seriesPlay, !model.isCaughtUp,
           let number = model.next.season, let summary = details.seasons.first(where: { $0.number == number }), let episodes = model.seasons.episodes[number] {
            let count = episodes.count == 1 ? "1 episode" : "\(episodes.count) episodes"
            rows.append(MenuRow(label: "Mark Season \(number) Watched", systemImage: "checkmark.circle", summary: "Marks \(count) watched, here and on \(server).") {
                Task {
                    if await model.markSeason(summary, episodes: episodes, watched: true) {
                        toast = Toast(message: "Season \(number) marked watched", systemImage: "checkmark.circle.fill")
                    }
                }
            })
        }
        return rows
    }

    /// Moves the series to `target`, or removes it for nil, and confirms the change
    private func change(_ details: SeriesDetails, to target: WatchState?) {
        Task {
            guard let change = await store.change(
                id: id, title: details.title, posterPath: details.posterPath,
                created: (details.regularSeasonsCount, details.totalEpisodesCount, details.status ?? ""),
                jellyfinID: details.jellyfinID, to: target, connection: connection
            ) else { return }
            toast = change.toast
            if let failure = await change.outcome.value { toast = failure }
        }
    }
}

/// One episode row's label: number, still with the biinge watched mark and resume bar, title, overview and runtime, or the "Not on" note dimmed when the library has no single item for it
private struct TVEpisodeRow: View {
    let connection: JellyfinConnection
    let episode: EpisodeSummary
    let isWatched: Bool
    /// The played share of the episode's Jellyfin resume position, nil for none
    let share: Double?

    var body: some View {
        let ticks = episode.runtime * 600_000_000
        let play = DetailsPlay(jellyfinID: episode.jellyfinID, isConnected: connection.isConnected)
        HStack(spacing: 36) {
            Text("\(episode.number)")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .trailing)
            PosterImage(title: episode.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: episode.posterPath, size: "w500"),
                        frame: CGSize(width: 384, height: 216), titleFont: .system(size: 26), titlePadding: 20)
                .overlay(alignment: .topLeading) {
                    if isWatched {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(rgb: 0xF4F4F2))
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .padding(12)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let share {
                        PlaybackBar(fraction: share, height: 7, inset: 14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 10) {
                Text(episode.title)
                    .font(.system(size: 31, weight: .semibold))
                    .lineLimit(1)
                Text(episode.overview)
                    .font(.system(size: 25))
                    .lineSpacing(5)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 20) {
                if let rating = episode.rating, rating > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color.biingePrimary)
                        Text(rating, format: .number.precision(.fractionLength(1)))
                    }
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rated \(rating.formatted(.number.precision(.fractionLength(1))))")
                }
                Text(play == .notOnServer ? "Not on \(connection.serverName ?? "server")" : duration(ticks: ticks))
                    .lineLimit(1)
            }
            .font(.system(size: 25))
            .foregroundStyle(.secondary)
        }
        .opacity(play == .notOnServer ? 0.45 : 1)
    }
}

/// A season tab: a capsule that fills while selected and turns light while focused
private struct SeasonTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Tab(label: configuration.label, isSelected: isSelected)
    }

    /// Reads focus from the environment, which a ButtonStyle itself can't see
    private struct Tab: View {
        let label: ButtonStyleConfiguration.Label
        let isSelected: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isFocused ? Color.biingeFocusText : Color.biingeText.opacity(isSelected ? 1 : 0.7))
                .padding(.horizontal, 30)
                .frame(height: 64)
                .background(isFocused ? Color.biingeFocusFill : Color.biingeText.opacity(isSelected ? 0.16 : 0), in: Capsule())
                // Reduce Motion keeps the light fill as the focus mark and drops the lift
                .scaleEffect(isFocused && !reduceMotion ? 1.08 : 1)
                .shadow(color: Color.biingeShadow.opacity(isFocused ? 0.45 : 0), radius: 20, y: 18)
                .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
        }
    }
}

/// An episode row: plain at rest, light and raised while focused
private struct EpisodeRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(label: configuration.label)
    }

    /// Reads focus from the environment, which a ButtonStyle itself can't see
    private struct Row: View {
        let label: ButtonStyleConfiguration.Label

        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .foregroundStyle(isFocused ? Color.biingeFocusText : Color.biingeText)
                .padding(.vertical, 20)
                .padding(.horizontal, 28)
                .background(isFocused ? Color.biingeFocusFill : .clear, in: RoundedRectangle(cornerRadius: 24))
                // Reduce Motion keeps the light fill as the focus mark and drops the lift
                .scaleEffect(isFocused && !reduceMotion ? 1.02 : 1)
                .shadow(color: Color.biingeShadow.opacity(isFocused ? 0.4 : 0), radius: 20, y: 18)
                .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
        }
    }
}

extension TVSeriesDetailsView {
    /// The loading skeleton in the header's layout: the poster beside the kind, title, meta, progress, buttons, overview and facts where they land (as tall as the page's column, so the poster stays put)
    private var skeleton: some View {
        HStack(alignment: .bottom, spacing: 72) {
            SkeletonBlock(cornerRadius: 20)
                .frame(width: 340, height: 510)
            VStack(alignment: .leading, spacing: 20) {
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 130, height: 28)
                SkeletonBlock(cornerRadius: 14)
                    .frame(width: 760, height: 150)
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 480, height: 29)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 420, height: 31)
                HStack(spacing: 22) {
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 300, height: 76)
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 260, height: 76)
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 76, height: 76)
                }
                .padding(.top, 8)
                SkeletonBlock(cornerRadius: 8)
                    .frame(maxWidth: 1080)
                    .frame(height: 86)
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 900, height: 30)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 96)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .loadingSkeleton(isHeld: $isSkeletonHeld)
    }

    /// The episode list's loading skeleton: the rows the season's last load returned, in the rows' own layout
    private var episodesSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<SkeletonRows.count(for: "episodes-\(id)-\(model?.season ?? 0)", screenful: 4), id: \.self) { _ in
                HStack(spacing: 36) {
                    SkeletonBlock(cornerRadius: 6)
                        .frame(width: 40, height: 36)
                        .frame(width: 64, alignment: .trailing)
                    SkeletonBlock(cornerRadius: 14)
                        .frame(width: 384, height: 216)
                    VStack(alignment: .leading, spacing: 16) {
                        SkeletonBlock(cornerRadius: 6)
                            .frame(width: 420, height: 31)
                        SkeletonBlock(cornerRadius: 6)
                            .frame(maxWidth: 820)
                            .frame(height: 25)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 28)
            }
        }
        .loadingSkeleton(isHeld: $isEpisodesSkeletonHeld)
    }
}
