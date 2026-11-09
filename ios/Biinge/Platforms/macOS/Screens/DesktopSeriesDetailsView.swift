import JellyfinAPI
import SwiftUI

/// Mac series details from biinge: poster, title, meta, the watched count, the white pill, list button and More, then the facts, the season tabs and episode rows, cast and crew, similar titles and recommendations
struct DesktopSeriesDetailsView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// The series' TMDB ID
    let id: Int
    /// The Jellyfin poster of the tile the details opened from, shown in place of the TMDB poster (nil for the TMDB poster)
    let libraryPoster: URL?

    /// The series, its seasons and the next episode, nil until the first load has the environment's store
    @State private var model: SeriesDetailsState?
    /// The list a click would remove the series from, which deletes its episode marks, nil when no confirmation shows
    @State private var untrack: WatchState?
    /// The episode whose details sheet shows, nil when none does
    @State private var openEpisode: EpisodeSummary?
    /// The confirmation of the last list or pin change, nil when none shows
    @State private var toast: Toast?
    /// The page's height, which caps the episode sheet's
    @State private var pageHeight: CGFloat = 0
    /// Set while the list menu shows under the list button
    @State private var isListMenuOpen = false
    /// Set while the page skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    /// Set while the episode list's skeleton holds its 500 ms
    @State private var isEpisodesSkeletonHeld = false
    @Environment(SeriesStore.self) private var store
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.macIsCovered) private var isCovered

    var body: some View {
        let details = model?.details
        let ended = connection.playbackEnded
        Group {
            if !isSkeletonHeld, let model, let details {
                // the page fades in as the skeleton leaves, and the swap animates nothing else
                page(model, details)
                    .macListMenu(isPresented: $isListMenuOpen) { listMenu(details) }
                    // search and the player overlay the stack, and hidden buttons still take key equivalents under them
                    .background { listMenu(details).shortcuts.disabled(isCovered) }
                    .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else if !isSkeletonHeld, let model, let failure = model.failure {
                ContentUnavailableView {
                    Label("Can’t reach Biinge", systemImage: "icloud.slash")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Retry") {
                        Task { await model.load() }
                    }
                }
                .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else {
                DetailsSkeleton(posterWidth: 260, isHeld: $isSkeletonHeld)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .navigationTitle(details?.title ?? "")
        .toast($toast)
        .alert(
            "Couldn’t change Watched",
            // the episode sheet shows its own failure, as an alert here would wait behind the sheet
            isPresented: Binding(get: { openEpisode == nil && model?.watchedFailure != nil }, set: { if !$0 { model?.watchedFailure = nil } })
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
        // the API matches the Jellyfin items for the connected account, so a new connection fetches the details and seasons again
        .task(id: connection.userID) {
            let model = model ?? SeriesDetailsState(apiClient: apiClient, store: store, connection: connection, seriesID: id)
            self.model = model
            await model.load()
        }
        // a mark that finishes a season moves the next episode into a season that may not have loaded yet
        .task(id: model?.next.season) {
            if let model, let number = model.next.season { await model.seasons.load(number) }
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
        let poster = Config.tmdbImageURL(path: details.posterPath, size: "w780")
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 44) {
                    header(model, details, poster: poster)
                    DesktopDetailFacts(facts: DetailFact.series(details, state: store.currentState(id: id)))
                        .entrance(after: 0.24)
                    if !details.seasons.isEmpty {
                        seasonList(model, details)
                            .entrance(after: 0.24)
                    }
                }
                .padding(.top, 100)
                .padding(.horizontal, 40)
                .padding(.bottom, 80)
                .background(alignment: .top) {
                    // the art blurred and dimmed behind the header, fading into the page before the episodes
                    DetailBackdrop(url: poster, height: 760, blur: 80, saturation: 1.4, bleed: 120, fadeStart: 0.3, topOverlap: 0)
                }
                DetailsRows(
                    connection: connection, apiClient: apiClient, itemID: details.jellyfinID, credits: details.credits,
                    facts: [],
                    recommendations: RecommendationsRow(
                        items: details.recommendations, state: store.currentState(id:),
                        poster: { Config.tmdbImageURL(path: $0.posterPath, size: "w342") },
                        route: { .title(.series($0.id)) }
                    )
                )
                .entrance(after: 0.24)
            }
        }
    }

    /// Poster beside the title, meta, watched count, the next episode's button, Want and Watched, and the overview
    private func header(_ model: SeriesDetailsState, _ details: SeriesDetails, poster: URL?) -> some View {
        let title = details.title
        let watched = model.progress?.watchedEpisodes.count ?? 0
        let total = details.totalEpisodesCount
        let seasons = details.regularSeasonsCount
        let meta = [DetailFact.release(details.releaseDate) ?? "", seasons == 1 ? "1 Season" : "\(seasons) Seasons", details.genres.prefix(3).joined(separator: ", ")]
        return HStack(alignment: .top, spacing: 48) {
            // the slot stays clear until the poster grows in, so the backdrop shows through
            PosterImage(title: title, cornerRadius: 0, poster: libraryPoster ?? poster, frame: CGSize(width: 260, height: 390), titleFont: .system(size: 14), titlePadding: 12)
                .environment(\.imageLoadsClear, true)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.biingeText.opacity(0.1), lineWidth: 1))
                .detailWatchedBadge(store.currentState(id: id) == .watched)
                .shadow(color: Color.biingeShadow.opacity(0.55), radius: 40, y: 34)
                .macMorphTarget(.series(id))
            // the text arrives 60 ms apart as the clicked poster grows into place
            VStack(alignment: .leading, spacing: 18) {
                Text("TV Show")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.75)
                    .entrance()
                Text(title)
                    .font(.system(size: title.count > 30 ? 52 : 72, weight: .bold))
                    .tracking((title.count > 30 ? 52 : 72) * -0.035)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .entrance()
                HStack(spacing: 16) {
                    Text(meta.filter { !$0.isEmpty }.joined(separator: " · "))
                        .opacity(0.8)
                    if let rating = details.rating, rating > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.biingePrimary)
                            Text(rating, format: .number.precision(.fractionLength(1)))
                                .fontWeight(.semibold)
                        }
                    }
                }
                .font(.system(size: 16))
                .entrance(after: 0.06)
                if total > 0 {
                    HStack(spacing: 14) {
                        Capsule()
                            .fill(Color.biingeText.opacity(0.22))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.biingeText).frame(width: 240 * min(Double(watched) / Double(total), 1))
                            }
                            .frame(width: 240, height: 4)
                        Text("\(watched) of \(total) episodes watched")
                            .font(.system(size: 14.5))
                            .opacity(0.75)
                    }
                    .entrance(after: 0.12)
                }
                actions(model, details)
                    .entrance(after: 0.12)
                Text(details.overview)
                    .font(.system(size: 18))
                    .lineSpacing(5)
                    .opacity(0.82)
                    .frame(maxWidth: 660, alignment: .leading)
                    .entrance(after: 0.18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The white pill from DetailPrimary for the offered episode, the list button and More, then the note for a series or next episode the library lacks, a missing or unreachable connection, the next air date, or a play Jellyfin marked played that biinge lacks
    @ViewBuilder
    private func actions(_ model: SeriesDetailsState, _ details: SeriesDetails) -> some View {
        let play = model.seriesPlay
        let episodePlay = model.nextPlay
        let next = model.next
        let state = store.currentState(id: id)
        let server = connection.serverName ?? "server"
        let offered: (season: Int, number: Int)? = if case .episode(let season, let episode) = next { (season, episode.number) } else { nil }
        // Jellyfin's played mark doesn't reach biinge by itself (episode counts, since an airing series never reaches Watched)
        let playedOnServer = model.seriesItem?.userData?.isPlayed == true
        // while the offered episode's season loads, the pill waits for it rather than offering the add
        let isPicking: Bool = if case .loading = next, play != .connect, play != .notOnServer { true } else { false }
        let primary = isPicking ? nil : DetailPrimary.series(
            play: episodePlay, state: state, episode: offered, position: model.nextPosition, caughtUp: model.isCaughtUp, playedOnServer: playedOnServer
        )
        HStack(spacing: 12) {
            if let primary {
                PrimaryPill(primary: primary, server: server) {
                    switch primary.action {
                    case .play(let jellyfinID):
                        // a fresh item, so the play resumes from the position Jellyfin holds now
                        attemptPlay {
                            guard let service = connection.service else { return }
                            await connection.play(try await service.item(id: jellyfinID))
                        }
                    case .move(let target):
                        change(details, to: target)
                    case .unreachable:
                        break
                    }
                }
                // the add folds away on Exit over Quick as the list button takes its place (Reduce Motion fades it)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            }
            ListButton(pill: DetailListPill(.series, state: state, isPinned: store.isPinned(id: id)), isOpen: $isListMenuOpen)
            // Start Over needs a stored position the server can play from
            let startOver: (label: String, play: () -> Void)? = if case .play = episodePlay, let nextItem = model.nextItem, let offered, model.nextPosition > 0 {
                ("Start S\(offered.season) · E\(offered.number) Over", { Task { await connection.play(nextItem, fromStart: true) } })
            } else {
                nil
            }
            // the offered episode's season, for a series on the server, once loaded and while biinge holds it unwatched
            let seasonMark: (number: Int, mark: () -> Void)? = if play != .connect, play != .notOnServer, let number = next.season, let summary = details.seasons.first(where: { $0.number == number }),
                                                                   let episodes = model.seasons.episodes[number],
                                                                   model.progress?.watchedSeasons.contains(summary.id) != true {
                (number, { markSeason(model, summary, episodes: episodes) })
            } else {
                nil
            }
            MoreMenu(kind: .series, id: id, apiClient: apiClient, startOver: startOver, markSeason: seasonMark)
        }
        .animation(MotionCurve.exit.animation(MotionDuration.quick), value: primary == nil)
        // the next episode waits on a season other than the shown one, so its error shows here (the shown season keeps its own)
        if let failed = next.failedSeason(failures: model.seasons.failures, shown: model.season), let failure = model.seasons.failures[failed] {
            HStack(spacing: 14) {
                Label("Couldn’t load season \(failed). \(failure)", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(rgb: 0xFF8A8D))
                Button("Retry") { Task { await model.seasons.load(failed) } }
            }
        }
        if let note = model.episodeNote {
            DesktopDetailNote(systemImage: note.systemImage, text: note.text)
        }
        let playedUnwatched = playedOnServer && state != .watched && model.progress?.watchedEpisodes.count ?? 0 < details.totalEpisodesCount
        if let note = PlayNote(play: play, server: connection.serverName, playedUnwatched: playedUnwatched) {
            switch note.kind {
            case .connect:
                // clearing Not Now brings back the connect screen
                DesktopDetailNote(systemImage: note.systemImage, text: note.text, link: "Connect Jellyfin") { connection.skippedConnect = false }
            case .unreachable:
                DesktopDetailNote(systemImage: note.systemImage, color: Color.biingeError, text: note.text, link: "Retry") {
                    Task { await connection.checkReachability() }
                }
            case .playedUnwatched:
                DesktopDetailNote(systemImage: note.systemImage, text: note.text, link: "Add to Watched") { change(details, to: .watched) }
            case .notOnServer, .seasonNotOnServer, .airs:
                DesktopDetailNote(systemImage: note.systemImage, text: note.text)
            }
        }
    }

    /// The list menu under the list button, which closes on a pick and confirms it with a toast (a removal asks first)
    private func listMenu(_ details: SeriesDetails) -> ListMenu {
        let state = store.currentState(id: id)
        let close = { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { isListMenuOpen = false } }
        return ListMenu(kind: .series, state: state, isPinned: store.isPinned(id: id), server: connection.serverName ?? "server") { target in
            close()
            change(details, to: target)
        } togglePin: {
            close()
            let pinned = !store.isPinned(id: id)
            Task { await store.setPinned(id: id, pinned: pinned) }
            toast = Toast(pinned: pinned)
        } remove: {
            close()
            // removing the series deletes its episode marks, so it asks first
            untrack = state
        }
    }

    /// Moves the series to `target`, or removes it for nil, and confirms the change (Watched marks every aired episode, here and on Jellyfin)
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

    /// Marks the season watched through the model with its toast (a failure shows the alert)
    private func markSeason(_ model: SeriesDetailsState, _ season: SeasonSummary, episodes: [EpisodeSummary]) {
        Task {
            if await model.markSeason(season, episodes: episodes, watched: true) {
                toast = Toast(message: "Season \(season.number) marked watched", systemImage: "checkmark.circle.fill")
            }
        }
    }
}

extension DesktopSeriesDetailsView {
    /// The season tabs with the shown season's count and length, then its episode rows
    private func seasonList(_ model: SeriesDetailsState, _ details: SeriesDetails) -> some View {
        let season = model.season
        let seasons = model.seasons
        let shown = details.seasons.first { $0.number == season }
        let rows = season.flatMap { seasons.episodes[$0] }
        let seasonMinutes = rows?.reduce(0) { $0 + $1.runtime } ?? 0
        // read out here, as what a sheet's closure reads alone doesn't update the view when it changes
        let maxHeight = pageHeight
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // a long series has more seasons than the window is wide, so the tabs scroll sideways
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(details.seasons) { item in
                            let isSelected = item.number == season
                            Button {
                                model.season = item.number
                                Task { await seasons.load(item.number) }
                            } label: {
                                Text(item.number == 0 ? "Specials" : "Season \(item.number)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .padding(.horizontal, 18)
                                    .frame(height: 36)
                                    .foregroundStyle(Color.biingeText.opacity(isSelected ? 1 : 0.72))
                                    .background(isSelected ? Color.biingeText.opacity(0.16) : .clear, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(3)
                    .background(Color.biingeText.opacity(0.06), in: Capsule())
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
                if let rows {
                    Text("\(rows.count == 1 ? "1 episode" : "\(rows.count) episodes") · \(duration(ticks: seasonMinutes * 600_000_000))")
                        .font(.system(size: 14.5))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            if !isEpisodesSkeletonHeld, let rows, let shown {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, episode in
                        let isWatched = model.progress.map { $0.watchedEpisodes.contains(episode.id) } ?? episode.watched
                        let isNext = episode.id == model.nextEpisode?.id
                        DesktopEpisodeRow(
                            connection: connection,
                            episode: episode,
                            isWatched: isWatched,
                            isNext: isNext,
                            share: seasons.share(episode),
                            open: { openEpisode = episode },
                            toggleWatched: { Task { await model.setWatched(!isWatched, episode: episode, season: shown, seasonEpisodes: rows) } }
                        )
                        .rowFade(at: index)
                    }
                }
                .sheet(item: $openEpisode) { episode in
                    // the sheet reads the episode's watched mark from the store, so the write takes the target it shows
                    DesktopEpisodeDetailsView(
                        connection: connection,
                        apiClient: apiClient,
                        seriesID: id,
                        seriesTitle: details.title,
                        creators: details.creators,
                        seasonNumber: shown.number,
                        episode: episode,
                        share: seasons.share(episode),
                        maxHeight: maxHeight,
                        setWatched: { await model.setWatched($0, episode: episode, season: shown, seasonEpisodes: rows) },
                        watchedFailure: Bindable(model).watchedFailure
                    )
                }
            } else if !isEpisodesSkeletonHeld, let number = season, let failure = seasons.failures[number] {
                HStack(spacing: 14) {
                    Label("Couldn’t load this season. \(failure)", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(rgb: 0xFF8A8D))
                    Button("Retry") {
                        Task { await seasons.load(number) }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                episodesSkeleton
            }
        }
    }

    /// The episode list's loading skeleton: the rows the season's last load returned, in the rows' own layout
    private var episodesSkeleton: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<SkeletonRows.count(for: "episodes-\(id)-\(model?.season ?? 0)", screenful: 6), id: \.self) { _ in
                HStack(spacing: 22) {
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 24, height: 22)
                        .frame(width: 40, alignment: .trailing)
                    SkeletonBlock(cornerRadius: 10)
                        .frame(width: 224, height: 126)
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBlock(cornerRadius: 4)
                            .frame(width: 260, height: 17)
                        SkeletonBlock(cornerRadius: 4)
                            .frame(maxWidth: 520)
                            .frame(height: 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
                .padding(.leading, 16)
                .padding(.trailing, 64)
            }
        }
        .loadingSkeleton(isHeld: $isEpisodesSkeletonHeld)
    }
}

/// One episode row: number, still with the biinge watched mark and resume bar, title, overview, runtime and Watched, highlighted for the next episode (a click opens the episode's details, and hovering the still offers Play of its own Jellyfin item)
struct DesktopEpisodeRow: View {
    let connection: JellyfinConnection
    let episode: EpisodeSummary
    let isWatched: Bool
    let isNext: Bool
    /// The played share of the episode's Jellyfin resume position, nil for none
    let share: Double?
    let open: () -> Void
    let toggleWatched: () -> Void

    @State private var isHovering = false
    @Environment(\.attemptPlay) private var attemptPlay

    var body: some View {
        let ticks = episode.runtime * 600_000_000
        let play = DetailsPlay(jellyfinID: episode.jellyfinID, isConnected: connection.isConnected)
        let startPlay = {
            guard case .play(let jellyfinID) = play else { return }
            // a fresh item, so the play resumes from the position Jellyfin holds now
            attemptPlay {
                guard let service = connection.service else { return }
                await connection.play(try await service.item(id: jellyfinID))
            }
        }
        let label = HStack(spacing: 22) {
            Text("\(episode.number)")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
            PosterImage(title: episode.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: episode.posterPath, size: "w500"),
                        frame: CGSize(width: 224, height: 126), titleFont: .system(size: 14), titlePadding: 12)
                .overlay(alignment: .topLeading) {
                    if isWatched {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(rgb: 0xF4F4F2))
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                            .padding(7)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let share {
                        // the mockup's white track over the art on any appearance
                        Capsule()
                            .fill(.white.opacity(0.3))
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(Color(rgb: 0xF4F4F2))
                                        .frame(width: proxy.size.width * share)
                                }
                            }
                            .frame(height: 4)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 9)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                if isNext {
                    Text(share.map { "RESUME · \(duration(ticks: Int(Double(ticks) * (1 - $0))).uppercased()) LEFT" } ?? "UP NEXT")
                        .font(.system(size: 12.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.biingeText)
                }
                Text(episode.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(episode.overview)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) {
                if let rating = episode.rating, rating > 0 {
                    HStack(spacing: 5) {
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
            .font(.system(size: 14.5))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.leading, 16)
        .contentShape(Rectangle())
        HStack(spacing: 16) {
            Button(action: open) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the episode’s details")
            .accessibilityActions {
                if case .play = play { Button("Play", action: startPlay) }
            }
            // the mockup's Play over the still while the pointer is on the row, above the row's own click
            .overlay(alignment: .leading) {
                if isHovering, case .play = play {
                    Button(action: startPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(rgb: 0x101014))
                            .frame(width: 46, height: 46)
                            .background(Color(rgb: 0xF4F4F2), in: Circle())
                            .frame(width: 224, height: 126)
                            .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Play")
                    .padding(.leading, 16 + 40 + 22)
                }
            }
            Button(action: toggleWatched) {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isWatched ? Color(rgb: 0x34C46F) : Color.biingeText.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isWatched ? "Mark as Unwatched" : "Mark as Watched")
            .accessibilityLabel(isWatched ? "Mark as Unwatched" : "Mark as Watched")
        }
        .padding(.trailing, 16)
        .background(isNext ? Color.biingeText.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 14))
        .onHover { isHovering = $0 }
    }
}
