import JellyfinAPI
import SwiftUI

struct MobileSeriesDetailsView: View {
    let seriesId: Int
    /// The Jellyfin poster of the tile the details opened from, shown in place of the TMDB poster (nil for the TMDB poster)
    var libraryPoster: URL?
    @Environment(\.apiClient) private var apiClient
    @Environment(SeriesStore.self) private var store
    /// Nil until the shell puts the connection in the environment, which reads as not connected
    @Environment(JellyfinConnection.self) private var connection: JellyfinConnection?
    @Environment(\.openURL) private var openURL
    @Environment(\.presentSeries) private var presentSeries
    @Environment(\.presentEpisode) private var presentEpisode

    /// The series, its seasons and the next episode, nil until the first load has the environment's client, store and connection
    @State private var model: SeriesDetailsState?
    /// Shows the Lists sheet
    @State private var showsLists = false
    /// Shows the More sheet
    @State private var showsMore = false
    /// Shows Connect Jellyfin over the details
    @State private var showsConnect = false
    /// The list a tap would remove the series from, which deletes its episode marks, nil when no confirmation shows
    @State private var untrack: WatchState?
    /// Bumped when a state change lands, so the haptic fires with the UI rather than on the tap
    @State private var stateChanges = 0
    /// Bumped on the lighter commits: ticking one episode, pinning and unpinning
    @State private var marks = 0
    /// The confirmation of the last list change, nil when none shows
    @State private var toast: Toast?
    /// Set while the page skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    /// Set while the episode list's skeleton holds its 500 ms
    @State private var isEpisodesSkeletonHeld = false

    var body: some View {
        let isConnected = connection?.isConnected == true
        let ended = connection?.playbackEnded ?? 0
        let details = model?.details
        ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView {
                    if !isSkeletonHeld, let model, let details {
                        // the content fades in as the skeleton leaves, and the swap animates nothing else
                        content(model, details)
                            .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
                    } else if isSkeletonHeld || model?.failure == nil {
                        DetailSkeleton(isHeld: $isSkeletonHeld)
                    } else {
                        DetailLoadError {
                            Task { await model?.load() }
                        }
                        .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
                    }
                }
                .scrollIndicators(.hidden)
                .task(id: details?.id) {
                    #if DEBUG
                    guard details != nil,
                          ProcessInfo.processInfo.environment["DEBUG_SCROLL_SEASONS"] == "1" else { return }
                    try? await Task.sleep(for: .milliseconds(700))
                    withAnimation { proxy.scrollTo("seasons", anchor: .top) }
                    #endif
                }
            }

            CloseButton()
            if let model, let details, hasMore(model, details) {
                DetailMoreButton { showsMore = true }
            }
        }
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsConnect) {
            if let connection, let apiClient { DetailConnectSheet(connection: connection, apiClient: apiClient) }
        }
        .sheet(isPresented: $showsLists) {
            if let details { listsSheet(details) }
        }
        // inside the failure alert, so Start Over's failed play shows over the details
        .sheet(isPresented: $showsMore) {
            if let model, let details { moreSheet(model, details) }
        }
        .detailPlayFailureAlert(connection)
        // the API matches the Jellyfin items for the connected account, so a new connection fetches the details and seasons again
        .task(id: connection?.userID) {
            guard let apiClient, let connection else { return }
            let model = model ?? SeriesDetailsState(apiClient: apiClient, store: store, connection: connection, seriesID: seriesId)
            self.model = model
            await model.load()
        }
        // a mark that finishes a season moves the next episode into a season that may not have loaded yet
        .task(id: model?.next.season) {
            if let model, let number = model.next.season { await model.seasons.load(number) }
        }
        // the Jellyfin reads, again after a connect and once a stopped play's report has gone out
        .task(id: "\(model?.nextEpisode?.jellyfinID ?? "")-\(isConnected)-\(ended)") { await model?.loadNextItem() }
        .task(id: "\(details?.jellyfinID ?? "")-\(isConnected)-\(ended)") { await model?.loadSeriesItem() }
        // a load starts the seasons over, so their shares load again for the new ones
        .task(id: "\(details?.jellyfinID ?? "")-\(model?.season ?? -1)-\(isConnected)-\(ended)-\(model.map { ObjectIdentifier($0.seasons).hashValue } ?? 0)") {
            await model?.loadShares()
        }
        .sensoryFeedback(.success, trigger: stateChanges)
        .sensoryFeedback(.impact(weight: .light), trigger: marks)
        .alert(
            "Couldn’t change Watched",
            isPresented: Binding(get: { model?.watchedFailure != nil }, set: { if !$0 { model?.watchedFailure = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(model?.watchedFailure ?? "")
        }
        .toast($toast)
    }

    private func content(_ model: SeriesDetailsState, _ series: SeriesDetails) -> some View {
        let watched = model.progress?.watchedEpisodes.count ?? 0
        let total = series.totalEpisodesCount
        let count = series.regularSeasonsCount
        let meta = [DetailFact.release(series.releaseDate) ?? "", count == 1 ? "1 Season" : "\(count) Seasons", series.genres.prefix(2).joined(separator: ", ")]
        return VStack(alignment: .leading, spacing: 32) {
            // the slot stays clear until the poster grows in, so the backdrop shows through
            PosterImage(path: series.posterPath, title: series.title, size: "w500", cornerRadius: 14, poster: libraryPoster)
                .environment(\.imageLoadsClear, true)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.biingeFill(0.1), lineWidth: 1))
                .detailWatchedBadge(store.currentState(id: seriesId) == .watched)
                .frame(width: 216)
                .shadow(color: Color.biingeShadow.opacity(0.55), radius: 35, y: 30)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                // the text arrives 60 ms apart as the sheet grows out of the poster
                Text("TV Show")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.biingeText.opacity(0.75))
                    .entrance()
                Text(series.title)
                    .font(.biingeLargeTitle)
                    .tracking(-1.2)
                    .entrance()
                HStack(spacing: 12) {
                    Text(meta.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(Color.biingeText.opacity(0.8))
                    if let rating = series.rating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .labelStyle(RatingLabelStyle())
                    }
                }
                .font(.subheadline)
                .entrance(after: 0.06)
                if total > 0, watched > 0 {
                    DetailProgress(fraction: Double(watched) / Double(total), caption: "\(watched) of \(total) episodes watched")
                        .entrance(after: 0.12)
                }
                actions(model, series)
                    .padding(.top, 4)
                    .entrance(after: 0.12)
                if !series.overview.isEmpty {
                    Text(series.overview)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(Color.biingeText.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .entrance(after: 0.18)
                }
            }
            .padding(.horizontal, 16)

            MobileDetailFacts(facts: DetailFact.series(series, state: store.currentState(id: seriesId)))
                .padding(.horizontal, 16)
                .entrance(after: 0.24)
            if !series.seasons.isEmpty {
                seasonList(model, series)
                    .entrance(after: 0.24)
            }
            if !series.credits.isEmpty {
                DetailSection(title: "Cast & Crew") { CreditsRow(credits: series.credits) }
                    .entrance(after: 0.24)
            }
            if !series.recommendations.isEmpty {
                DetailSection(title: "Recommendations") { recommendationsRow(series.recommendations) }
                    .entrance(after: 0.24)
            }
        }
        .padding(.top, 72)
        .padding(.bottom, 48)
        // pinned to the scroll view's width, because a page answering a pixel wider pans sideways
        .containerRelativeFrame(.horizontal, alignment: .leading)
        .background(alignment: .top) {
            DetailBackdrop(url: Config.tmdbImageURL(path: series.posterPath, size: "w780"))
        }
    }

    /// The white pill of the next episode or step beside the list pill, then the note on what keeps the next episode from playing, or the played mark biinge lacks
    @ViewBuilder
    private func actions(_ model: SeriesDetailsState, _ series: SeriesDetails) -> some View {
        let state = store.currentState(id: seriesId)
        let server = connection?.serverName ?? "server"
        let isPlayed = model.seriesItem?.userData?.isPlayed == true
        let next = model.next
        let offered: (season: Int, number: Int)? = if case .episode(let number, let episode) = next { (number, episode.number) } else { nil }
        // caught up, the pick offers S1 · E1, so the pill reads Play Again · S1 · E1
        let primary = DetailPrimary.series(
            play: model.nextPlay, state: state, episode: offered, position: model.nextPosition, caughtUp: model.isCaughtUp, playedOnServer: isPlayed
        )
        DetailActionRow(primary: primary, connection: connection) { change(series, to: $0) } secondary: {
            DetailListButton(pill: DetailListPill(.series, state: state, isPinned: store.isPinned(id: seriesId)), fills: primary == nil) {
                showsLists = true
            }
        }
        // the next episode waits on a season other than the shown one, so its error shows here (the shown season keeps its own)
        if let failed = next.failedSeason(failures: model.seasons.failures, shown: model.season), let failure = model.seasons.failures[failed] {
            HStack(spacing: 12) {
                Label("Couldn’t load season \(failed). \(failure)", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.biingeError)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await model.seasons.load(failed) }
                } label: {
                    Text("Retry")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color.biingeFill(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        if let note = model.episodeNote {
            DetailNote(text: note.text, systemImage: note.systemImage)
        }
        // Jellyfin's played mark doesn't reach biinge by itself
        let playedUnwatched = isPlayed && state != .watched && model.progress?.watchedEpisodes.count ?? 0 < series.totalEpisodesCount
        if let note = PlayNote(play: model.seriesPlay, server: connection?.serverName, playedUnwatched: playedUnwatched) {
            switch note.kind {
            case .connect:
                DetailNote(text: note.text, systemImage: note.systemImage, cta: "Connect…") { showsConnect = true }
            case .unreachable:
                DetailNote(text: note.text, systemImage: note.systemImage, tint: .biingeError, cta: "Retry") {
                    Task {
                        await connection?.checkReachability()
                        if connection?.isUnreachable == true { toast = Toast(message: "Still can’t reach \(server)", systemImage: nil) }
                    }
                }
            case .playedUnwatched:
                DetailNote(text: note.text, systemImage: note.systemImage, cta: "Add to Watched") { change(series, to: .watched) }
            case .notOnServer, .seasonNotOnServer, .airs:
                DetailNote(text: note.text, systemImage: note.systemImage)
            }
        }
    }

    /// The season pills, the shown season's count and length, then the next episode's Continue card among compact rows
    private func seasonList(_ model: SeriesDetailsState, _ series: SeriesDetails) -> some View {
        let season = model.season
        let progress = model.progress
        let shown = series.seasons.first { $0.number == season }
        let rows = season.flatMap { model.seasons.episodes[$0] }
        let seasonMinutes = rows?.reduce(0) { $0 + $1.runtime } ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            // a long series has more seasons than the screen is wide, so the pills scroll sideways
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(series.seasons) { item in
                        let isSelected = item.number == season
                        Button {
                            model.season = item.number
                            Task { await model.seasons.load(item.number) }
                        } label: {
                            Text(item.number == 0 ? "Specials" : "Season \(item.number)")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? Color.biingeText : Color.biingeTextSecondary)
                                .padding(.horizontal, 15)
                                .frame(minHeight: 38)
                                .background(isSelected ? Color.biingeFill(0.14) : .clear, in: Capsule())
                                // the track's inset counts toward each pill, so every touch target is at least 44 pt tall
                                .padding(.vertical, 3)
                                .padding(.horizontal, 1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
                .background(Color.biingeFill(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.biingeFill(0.06), lineWidth: 1))
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)

            if !isEpisodesSkeletonHeld, let rows, let shown {
                Text("\(rows.count == 1 ? "1 episode" : "\(rows.count) episodes") · \(duration(ticks: seasonMinutes * 600_000_000))")
                    .font(.footnote)
                    .foregroundStyle(Color.biingeTextSecondary)
                    .padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, episode in
                        let isWatched = progress.map { $0.watchedEpisodes.contains(episode.id) } ?? episode.watched
                        let open = { presentEpisode(seriesId, shown.number, episode.number) }
                        Group {
                            if episode.id == model.nextEpisode?.id {
                                let playID: String? = if case .play(let id) = DetailsPlay(jellyfinID: episode.jellyfinID, isConnected: connection?.isConnected == true) { id } else { nil }
                                ContinueEpisodeCard(episode: episode, share: model.seasons.share(episode), connection: connection, playID: playID, open: open)
                                .padding(.vertical, 6)
                            } else {
                                SeriesEpisodeRow(episode: episode, isWatched: isWatched, share: model.seasons.share(episode), open: open) {
                                    marks += 1
                                    Task { await model.setWatched(!isWatched, episode: episode, season: shown, seasonEpisodes: rows) }
                                }
                            }
                        }
                        .rowFade(at: index)
                    }
                }
                .padding(.horizontal, 16)

                if !rows.isEmpty {
                    let seasonWatched = progress?.watchedSeasons.contains(shown.id) == true
                    Button {
                        // the store shows the mark before its write goes out, so the haptic fires with it
                        stateChanges += 1
                        Task { await model.markSeason(shown, episodes: rows, watched: !seasonWatched) }
                    } label: {
                        Label(seasonWatched ? "Unmark Season" : "Mark Season Watched", systemImage: seasonWatched ? "arrow.uturn.backward" : "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.biingeFill(0.1), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .padding(.horizontal, 16)
                }
            } else if !isEpisodesSkeletonHeld, let number = season, let failure = model.seasons.failures[number] {
                VStack(spacing: 12) {
                    Label("Couldn’t load this season. \(failure)", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.biingeError)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await model.seasons.load(number) }
                    } label: {
                        Text("Retry")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(Color.biingeFill(0.12), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding(.horizontal, 16)
            } else if isEpisodesSkeletonHeld || season != nil {
                // the rows the season's last load returned, in the rows' own layout
                VStack(spacing: 0) {
                    ForEach(0..<SkeletonRows.count(for: "episodes-\(seriesId)-\(season ?? 0)", screenful: 10), id: \.self) { _ in
                        HStack(spacing: 12) {
                            SkeletonBlock(cornerRadius: 4)
                                .frame(width: 22, height: 17)
                            SkeletonBlock(cornerRadius: 4)
                                .frame(width: 180, height: 15)
                            Spacer(minLength: 0)
                            SkeletonBlock(cornerRadius: 11)
                                .frame(width: 22, height: 22)
                                .padding(11)
                        }
                        .frame(minHeight: 52)
                    }
                }
                .padding(.horizontal, 16)
                .loadingSkeleton(isHeld: $isEpisodesSkeletonHeld)
            }
        }
        .id("seasons")
    }
}

extension MobileSeriesDetailsView {
    private func recommendationsRow(_ items: [Recommendation]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        presentSeries(item.id)
                    } label: {
                        PosterImage(path: item.posterPath, title: item.title, size: "w342", cornerRadius: 10).frame(width: 112)
                            .trackedBadge(.series(item.id))
                    }
                    .buttonStyle(.pressable)
                    .detailTransitionSource("series-\(item.id)")
                }
            }
            .padding(.horizontal)
        }
    }

    /// The Lists sheet: Want to Watch, Watching and Watched, Pin in Want and Watching, and Remove, which asks first as it deletes the show's episode marks
    private func listsSheet(_ series: SeriesDetails) -> some View {
        let state = store.currentState(id: seriesId)
        return DetailListsSheet(
            kind: .series, title: series.title, server: connection?.serverName ?? "Jellyfin",
            state: state, isPinned: store.isPinned(id: seriesId)
        ) { target in
            showsLists = false
            change(series, to: target)
        } pin: { pinned in
            showsLists = false
            Task {
                await store.setPinned(id: seriesId, pinned: pinned)
                toast = Toast(pinned: pinned)
                marks += 1
            }
        } remove: {
            untrack = state
        }
        // over the sheet, which stays open on Cancel
        .confirmationDialog(
            "Remove \(series.title) from \(untrack == .want ? "Want" : untrack == .watching ? "Watching" : "Watched")?",
            isPresented: Binding(get: { untrack != nil }, set: { if !$0 { untrack = nil } }),
            titleVisibility: .visible,
            presenting: untrack
        ) { _ in
            Button("Remove", role: .destructive) {
                showsLists = false
                change(series, to: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Biinge also deletes every episode you marked watched in this show.")
        }
    }

    /// The More sheet: Start Over for the next episode once started on the server, Mark Season Watched and Watch Trailer
    private func moreSheet(_ model: SeriesDetailsState, _ series: SeriesDetails) -> some View {
        DetailMenuSheet(title: "More", subtitle: series.title) {
            if let connection, case .play(let jellyfinID) = model.nextPlay, model.nextPosition > 0, case .episode(let number, let episode) = model.next {
                DetailStartOverRow(title: "Start S\(number) · E\(episode.number) Over", connection: connection, jellyfinID: jellyfinID) { showsMore = false }
            }
            if let mark = seasonMark(model, series) {
                let count = mark.unwatched == 1 ? "1 episode" : "\(mark.unwatched) episodes"
                DetailMenuButton(
                    systemImage: "checkmark.circle",
                    title: "Mark Season \(mark.season.number) Watched",
                    summary: "Marks \(count) watched, here and on \(connection?.serverName ?? "server")."
                ) {
                    showsMore = false
                    // the store shows the mark before its write goes out, so the haptic fires with it
                    stateChanges += 1
                    Task { await model.markSeason(mark.season, episodes: mark.episodes, watched: true) }
                }
            }
            if let trailer = trailerURL(series) {
                DetailMenuButton(systemImage: "play.rectangle", title: "Watch Trailer") {
                    showsMore = false
                    openURL(trailer)
                }
            }
        }
    }

    /// Whether the More sheet has a row to show, so ••• stays away instead of opening an empty sheet
    private func hasMore(_ model: SeriesDetailsState, _ series: SeriesDetails) -> Bool {
        // Start Over shows once the next episode is started on the server
        let startsOver = if case .play = model.nextPlay { model.nextPosition > 0 } else { false }
        return startsOver || trailerURL(series) != nil || seasonMark(model, series) != nil
    }

    /// The next episode's season with its episodes and how many of them biinge doesn't hold as watched, while the series plays on the server and the user isn't caught up (nil otherwise, and until the season loads)
    private func seasonMark(_ model: SeriesDetailsState, _ series: SeriesDetails) -> (season: SeasonSummary, episodes: [EpisodeSummary], unwatched: Int)? {
        guard case .play = model.seriesPlay, !model.isCaughtUp, let number = model.next.season,
              let season = series.seasons.first(where: { $0.number == number }), let episodes = model.seasons.episodes[number] else { return nil }
        let unwatched = episodes.filter { episode in !(model.progress.map { $0.watchedEpisodes.contains(episode.id) } ?? episode.watched) }.count
        return unwatched > 0 ? (season, episodes, unwatched) : nil
    }

    /// The series' YouTube trailer, nil when it has none
    private func trailerURL(_ series: SeriesDetails) -> URL? {
        series.videos.first.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.key)") }
    }

    /// Moves the series to `target`, or removes it for nil, and confirms the change
    private func change(_ series: SeriesDetails, to target: WatchState?) {
        Task {
            guard let change = await store.change(
                id: seriesId, title: series.title, posterPath: series.posterPath,
                created: (series.regularSeasonsCount, series.totalEpisodesCount, series.status ?? ""),
                jellyfinID: series.jellyfinID, to: target, connection: connection
            ) else { return }
            toast = change.toast
            stateChanges += 1
            if let failure = await change.outcome.value { toast = failure }
        }
    }
}

/// The next episode, expanded: its still, Continue or Up Next, the title, its resume bar or runtime and synopsis, and a round Play while the server holds it
private struct ContinueEpisodeCard: View {
    let episode: EpisodeSummary
    /// The played share of the episode's Jellyfin resume position, nil for none
    let share: Double?
    let connection: JellyfinConnection?
    /// The episode's Jellyfin item to play, nil when it can't play here
    let playID: String?
    let open: () -> Void
    /// Read here rather than passed in, so the sheet's own failure alert catches the play
    @Environment(\.attemptPlay) private var attemptPlay

    var body: some View {
        let ticks = episode.runtime * 600_000_000
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    CachedImage(url: Config.tmdbImageURL(path: episode.posterPath, size: "w300"), maxPixel: 300) { Color.biingeSecondaryCard }
                        .frame(width: 112, height: 63)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(share != nil ? "CONTINUE" : "UP NEXT") · E\(episode.number)")
                            .font(.caption.weight(.bold))
                            .tracking(0.5)
                            .foregroundStyle(Color.biingeRating)
                        Text(episode.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // room for the Play button laid over the card
                    Color.clear.frame(width: playID == nil ? 0 : 44, height: 1)
                }
                if let share {
                    DetailProgress(fraction: share, caption: "\(duration(ticks: Int(Double(ticks) * (1 - share)))) left")
                } else if ticks > 0 {
                    Text(duration(ticks: ticks))
                        .font(.footnote)
                        .foregroundStyle(Color.biingeTextSecondary)
                }
                if !episode.overview.isEmpty {
                    Text(episode.overview)
                        .font(.subheadline)
                        .foregroundStyle(Color.biingeTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.biingeFill(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.biingeFill(0.07), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows the episode’s details")
        .overlay(alignment: .topTrailing) {
            if let playID {
                Button {
                    // a fresh item, so the play resumes from the position Jellyfin holds now
                    attemptPlay {
                        guard let connection, let service = connection.service else { return }
                        await connection.play(try await service.item(id: playID))
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.biingeBackground)
                        .frame(width: 44, height: 44)
                        .background(Color.biingeText, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(share != nil ? "Resume" : "Play")
                // centred on the still beside it
                .padding(.top, 12 + (63 - 44) / 2)
                .padding(.trailing, 12)
            }
        }
    }
}

/// A compact episode row: number, title, resume bar when Jellyfin holds a position, rating, runtime, and the trailing watched control
private struct SeriesEpisodeRow: View {
    let episode: EpisodeSummary
    let isWatched: Bool
    /// The played share of the episode's Jellyfin resume position, nil for none
    let share: Double?
    let open: () -> Void
    let toggleWatched: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Text("\(episode.number)")
                        .font(.custom("Archivo-SemiBold", size: 17, relativeTo: .body))
                        .foregroundStyle(Color.biingeTextTertiary)
                        .frame(minWidth: 22, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(episode.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(isWatched ? Color.biingeTextSecondary : Color.biingeText)
                            .lineLimit(1)
                        if let share {
                            Capsule()
                                .fill(Color.biingeFill(0.2))
                                .overlay(alignment: .leading) {
                                    GeometryReader { proxy in
                                        Capsule().fill(Color.biingeText).frame(width: proxy.size.width * min(max(share, 0), 1))
                                    }
                                }
                                .frame(height: 3)
                                .accessibilityLabel("Playback progress")
                                .accessibilityValue("\(Int((share * 100).rounded())) percent")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let rating = episode.rating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .labelStyle(RatingLabelStyle())
                            .font(.footnote)
                            .fixedSize()
                            .accessibilityLabel("Rated \(String(format: "%.1f", rating))")
                    }
                    if episode.runtime > 0 {
                        Text(duration(ticks: episode.runtime * 600_000_000))
                            .font(.footnote)
                            .foregroundStyle(Color.biingeTextTertiary)
                            .fixedSize()
                    }
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Shows the episode’s details")
            Button(action: toggleWatched) {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isWatched ? Color.biingeTextSecondary : Color.biingeTextTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWatched ? "Mark as Unwatched" : "Mark as Watched")
        }
    }
}
