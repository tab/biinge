import SwiftUI

struct TvDetailView: View {
    let seriesId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(TvStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.presentSeries) private var presentSeries

    @State private var details: SeriesDetails?
    @State private var isLoading = true
    @State private var showMenu = false
    /// Serializes progress writes and versions optimistic mutations so only the newest applies state
    @State private var progressWrites: Task<Void, Never>?
    @State private var progressGeneration = 0

    /// Progress lives in the store so marks made in an episode sheet update this screen instantly
    private var progress: WatchProgress? {
        store.progress(id: seriesId)
    }

    private var watchedEpisodeIds: Set<Int> {
        Set(progress?.watchedEpisodes ?? [])
    }

    private var watchedSeasonIds: Set<Int> {
        Set(progress?.watchedSeasons ?? [])
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView {
                    if let details {
                        content(details)
                    } else if isLoading {
                        ProgressView().tint(Color.biingeLoader)
                            .frame(maxWidth: .infinity).padding(.top, 160)
                    } else {
                        DetailLoadError()
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

            closeButton
        }
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .overlay {
            if showMenu, let details {
                TvActionMenu(
                    posterPath: details.posterPath,
                    state: store.currentState(id: seriesId),
                    pinned: store.isPinned(id: seriesId),
                    onAction: { action in Task { await handleMenu(action, details) } },
                    onCancel: { withAnimation(.easeOut(duration: 0.15)) { showMenu = false } }
                )
            }
        }
    }

    private func content(_ series: SeriesDetails) -> some View {
        VStack(spacing: 0) {
            PosterImage(path: series.posterPath, title: series.title, size: "w500", cornerRadius: 12)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.7 }
                .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                .overlay(alignment: .bottomTrailing) {
                    if let key = series.videos.first?.key {
                        playButton(key).padding(12)
                    }
                }
                .padding(.top, 64)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text(series.title).font(.biingeTitle1).foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    if let rating = series.rating, rating > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(Color.biingePrimary)
                            Text(String(format: "%.1f", rating)).font(.system(size: 24, weight: .heavy)).foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 15)

                HStack {
                    Text(formatDate(series.releaseDate)).foregroundStyle(Color.biingeGraniteGray)
                    Spacer()
                    statusPill(series.status)
                }
                .font(.biingeCallout)
                .padding(.horizontal, 15)

                TvActionsView(seriesId: seriesId, details: series, showMenu: $showMenu)
                    .padding(.horizontal, 15)

                if !series.overview.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Synopsis").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray)
                        Text(series.overview).font(.biingeBody).foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 15)
                }

                if !series.seasons.isEmpty {
                    seasonsSection(series)
                }
                if !series.credits.isEmpty {
                    DetailSection(title: "Cast and crew") { CreditsRow(credits: series.credits) }
                }
                if !series.recommendations.isEmpty {
                    recommendationsSection(series.recommendations)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCardBackground()
        }
    }

    private func seasonsSection(_ series: SeriesDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray).padding(.horizontal, 15)
            SeasonsView(
                seasons: series.seasons,
                showId: seriesId,
                watchedEpisodeIds: watchedEpisodeIds,
                watchedSeasonIds: watchedSeasonIds,
                onMarkEpisode: markEpisode,
                onMarkSeason: markSeason
            )
        }
        .id("seasons")
    }

    private func recommendationsSection(_ items: [Recommendation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommendations").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray).padding(.horizontal, 15)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            presentSeries(item.id)
                        } label: {
                            PosterImage(path: item.posterPath, title: item.title, size: "w185").frame(width: 120)
                                .overlay(alignment: .topLeading) {
                                    if isTracked(item) { WatchedBadge() }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
            }
        }
    }

    /// Live store membership, with the response's snapshot as fallback until the library loads
    private func isTracked(_ item: Recommendation) -> Bool {
        store.currentState(id: item.id) != nil
            || (!store.hasLoaded && (item.state ?? WatchState.none) != WatchState.none)
    }

    private func playButton(_ key: String) -> some View {
        Button {
            if let url = URL(string: "https://www.youtube.com/watch?v=\(key)") { openURL(url) }
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5), in: Circle())
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Close")
        .padding(.leading, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func statusPill(_ status: String?) -> some View {
        if let status, !status.isEmpty {
            Text(status)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.biingeTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .overlay { Capsule().strokeBorder(Color.biingeTextSecondary, lineWidth: 2) }
        }
    }

    private func formatDate(_ raw: String?) -> String {
        guard let raw, raw.count >= 10 else { return "" }
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return "" }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        // load the library too — opened from Search, the state pill would read an empty store
        async let libraryLoad: Void = store.loadIfNeeded()
        async let detail = try? await apiClient.seriesDetails(id: seriesId)
        async let prog = try? await apiClient.progress(showId: seriesId)
        details = await detail
        isLoading = false
        if let details {
            store.refreshMetadata(id: seriesId, title: details.title, posterPath: details.posterPath)
        }
        await libraryLoad
        if details != nil, let fetched = await prog {
            setProgress(fetched)
        }
    }

    private func handleMenu(_ action: TvActionMenu.MenuAction, _ series: SeriesDetails) async {
        switch action {
        case .toggle(let target):
            await store.toggle(
                id: seriesId, title: series.title, posterPath: series.posterPath,
                seasonsCount: series.regularSeasonsCount, episodesCount: series.totalEpisodesCount,
                status: series.status ?? "", target: target
            )
        case .pin:
            await store.setPinned(id: seriesId, pinned: true)
        case .unpin:
            await store.setPinned(id: seriesId, pinned: false)
        }
    }

    private func markEpisode(season: SeasonSummary, episodes: [EpisodeSummary], episode: EpisodeSummary, watched: Bool) async {
        guard let apiClient, let details else { return }
        let optimistic = baseProgress.togglingEpisode(
            id: episode.id, watched: watched, seasonId: season.id,
            seasonEpisodes: episodes, totalSeasons: details.regularSeasonsCount,
            showStatus: details.status
        )
        let series = progressSeries(details)
        applyOptimistic(optimistic) {
            if watched {
                let body = MarkEpisodeBody(
                    series: series,
                    season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                    episode: ProgressEpisodeMeta(title: episode.title, posterPath: episode.posterPath, runtime: episode.runtime, airDate: episode.airDate ?? "")
                )
                return try await apiClient.markEpisode(showId: seriesId, seasonId: season.id, episodeId: episode.id, body)
            } else {
                return try await apiClient.unmarkEpisode(showId: seriesId, seasonId: season.id, episodeId: episode.id)
            }
        }
    }

    private func markSeason(_ season: SeasonSummary, _ episodes: [EpisodeSummary], _ watched: Bool) async {
        guard let apiClient, let details else { return }
        let optimistic = baseProgress.togglingSeason(
            id: season.id, episodeIds: episodes.map(\.id),
            watched: watched, totalSeasons: details.regularSeasonsCount,
            showStatus: details.status
        )
        let series = progressSeries(details)
        applyOptimistic(optimistic) {
            if watched {
                let body = MarkSeasonBody(
                    series: series,
                    season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                    episodes: episodes.map {
                        ProgressEpisode(id: $0.id, title: $0.title, posterPath: $0.posterPath, runtime: $0.runtime, airDate: $0.airDate ?? "")
                    }
                )
                return try await apiClient.markSeason(showId: seriesId, seasonId: season.id, body)
            } else {
                return try await apiClient.unmarkSeason(showId: seriesId, seasonId: season.id)
            }
        }
    }

    // MARK: - Optimistic progress plumbing

    /// The progress a mutation builds on: the loaded value, or an empty baseline before the fetch lands
    private var baseProgress: WatchProgress {
        progress ?? WatchProgress(
            id: seriesId,
            state: store.currentState(id: seriesId) ?? .none,
            trackedState: store.currentState(id: seriesId),
            watchedSeasons: [],
            watchedEpisodes: []
        )
    }

    private func progressSeries(_ details: SeriesDetails) -> ProgressSeries {
        ProgressSeries(
            title: details.title,
            posterPath: details.posterPath,
            seasonsCount: details.regularSeasonsCount,
            episodesCount: details.totalEpisodesCount,
            status: details.status ?? ""
        )
    }

    /// Show `optimistic` immediately, enqueue the serialized write, and let only the newest mutation reconcile
    private func applyOptimistic(_ optimistic: WatchProgress, write: @escaping () async throws -> WatchProgress) {
        progressGeneration += 1
        let generation = progressGeneration
        let snapshot = progress
        setProgress(optimistic)

        let prior = progressWrites
        progressWrites = Task {
            await prior?.value
            do {
                let updated = try await write()
                guard generation == progressGeneration else { return }
                setProgress(updated)
            } catch {
                guard generation == progressGeneration else { return }
                if let fresh = try? await apiClient?.progress(showId: seriesId), generation == progressGeneration {
                    setProgress(fresh)
                } else if generation == progressGeneration, let snapshot {
                    setProgress(snapshot)
                }
            }
        }
    }

    /// One funnel into the store: this screen's checkmarks, episode sheets above, and the grid
    private func setProgress(_ value: WatchProgress) {
        guard let details else { return }
        store.apply(
            value, id: seriesId,
            title: details.title, posterPath: details.posterPath,
            episodesCount: details.totalEpisodesCount, pinned: details.pinned
        )
    }
}

/// The action row on a series: white state pills, or a single accent pill when tracked
struct TvActionsView: View {
    let seriesId: Int
    let details: SeriesDetails
    @Binding var showMenu: Bool
    @Environment(TvStore.self) private var store

    private var inProduction: Bool {
        switch details.status {
        case "Returning Series", "In Production", "Planned", "Pilot": return true
        default: return false
        }
    }

    var body: some View {
        let state = store.currentState(id: seriesId)
        Group {
            if let state, state != .none {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showMenu = true }
                } label: {
                    Text(state.rawValue.capitalized)
                        .font(.biingeCallout).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Color.biingeAccent, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    actionPill("Want") { toggle(.want) }
                    actionPill(inProduction ? "Watching" : "Watched") { toggle(inProduction ? .watching : .watched) }
                }
            }
        }
    }

    private func toggle(_ target: WatchState) {
        Task {
            await store.toggle(
                id: seriesId, title: details.title, posterPath: details.posterPath,
                seasonsCount: details.regularSeasonsCount, episodesCount: details.totalEpisodesCount,
                status: details.status ?? "", target: target
            )
        }
    }

    private func actionPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.biingeCallout).fontWeight(.semibold)
                .foregroundStyle(Color.biingeBackground)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Color.biingeText, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The action menu shown when tapping a tracked show's state pill
struct TvActionMenu: View {
    let posterPath: String
    let state: WatchState?
    let pinned: Bool
    let onAction: (MenuAction) -> Void
    let onCancel: () -> Void

    enum MenuAction {
        case toggle(WatchState)
        case pin, unpin
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.4).ignoresSafeArea()

            Button(action: onCancel) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()

            VStack(spacing: 28) {
                PosterImage(path: posterPath, title: "", size: "w342", cornerRadius: 12)
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.55 }
                    .onTapGesture { onCancel() }

                VStack(spacing: 2) {
                    ForEach(options, id: \.title) { option in
                        Button(action: option.action) {
                            Text(option.title)
                                .font(.biingeBody).fontWeight(.semibold)
                                .foregroundStyle(Color.biingeText.opacity(0.7))
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.biingeBody).fontWeight(.semibold)
                            .foregroundStyle(Color.biingeText.opacity(0.7))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
        }
        .transition(.opacity)
    }

    private var options: [(title: String, action: () -> Void)] {
        let pin: (title: String, action: () -> Void) = (pinned ? "Unpin" : "Pin", { onAction(pinned ? .unpin : .pin) })
        switch state {
        case .want:
            return [
                ("Remove from Want", { onAction(.toggle(.want)) }),
                ("Move to Watched", { onAction(.toggle(.watched)) }),
                pin,
            ]
        case .watching:
            return [
                ("Remove from Watching", { onAction(.toggle(.watching)) }),
                ("Move to Want", { onAction(.toggle(.want)) }),
                pin,
            ]
        case .watched:
            return [
                ("Remove from Watched", { onAction(.toggle(.watched)) }),
                ("Move to Want", { onAction(.toggle(.want)) }),
                pin,
            ]
        default:
            return [
                ("Want", { onAction(.toggle(.want)) }),
                ("Watched", { onAction(.toggle(.watched)) }),
            ]
        }
    }
}

/// Horizontal season selector with the selected season's episode list and a mark-season action
private struct SeasonsView: View {
    let seasons: [SeasonSummary]
    let showId: Int
    let watchedEpisodeIds: Set<Int>
    let watchedSeasonIds: Set<Int>
    let onMarkEpisode: (SeasonSummary, [EpisodeSummary], EpisodeSummary, Bool) async -> Void
    let onMarkSeason: (SeasonSummary, [EpisodeSummary], Bool) async -> Void

    @Environment(\.apiClient) private var apiClient
    @State private var selected: SeasonSummary?
    @State private var episodes: [EpisodeSummary] = []
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?
    /// Episodes already fetched this visit, keyed by season id, so switching back is instant
    @State private var episodesBySeason: [Int: [EpisodeSummary]] = [:]
    /// Once the user picks or marks a season, stop auto-selecting so the view never jumps
    @State private var didUserSelect = false
    /// Set on auto-select to scroll the strip so the chosen season pill is revealed
    @State private var scrollTarget: Int?

    /// The season to open by default: the earliest not-fully-watched season, or the last when all are watched
    private var defaultSeason: SeasonSummary? {
        let regular = seasons.filter { $0.number > 0 }
        let ordered = (regular.isEmpty ? seasons : regular).sorted { $0.number < $1.number }
        return ordered.first { !watchedSeasonIds.contains($0.id) } ?? ordered.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons) { season in
                            let isActive = selected?.id == season.id
                            Button {
                                didUserSelect = true
                                select(season)
                            } label: {
                                Text(season.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(isActive ? Color.biingeBackground : Color.biingeGrayDark)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(isActive ? Color.biingeText : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .id(season.id)
                        }
                    }
                    .padding(.horizontal, 15)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                }
            }

            if isLoading {
                ProgressView().tint(Color.biingeLoader)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                // A List gives native, system-driven swipe actions that never fight
                // the parent ScrollView (a custom DragGesture does). Scrolling is
                // disabled so the outer scroll drives, and the height is fixed to the
                // rows since a scroll-disabled List does not self-size.
                List {
                    ForEach(episodes) { episode in
                        EpisodeRow(
                            showId: showId,
                            seasonNumber: selected?.number ?? 0,
                            episode: episode,
                            isWatched: watchedEpisodeIds.contains(episode.id)
                        ) { watched in
                            didUserSelect = true
                            if let season = selected {
                                await onMarkEpisode(season, episodes, episode, watched)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(episodes.count) * EpisodeRow.height)

                if let season = selected, !episodes.isEmpty {
                    let seasonWatched = watchedSeasonIds.contains(season.id)
                    Button {
                        didUserSelect = true
                        Task { await onMarkSeason(season, episodes, !seasonWatched) }
                    } label: {
                        Text(seasonWatched ? "Remove Watched" : "Watched")
                            .font(.biingeCallout).fontWeight(.semibold)
                            .foregroundStyle(Color.biingeBackground)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Color.biingeText, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 15)
                    .padding(.top, 4)
                }
            }
        }
        .task { autoSelect() }
        .onChange(of: watchedSeasonIds) { autoSelect() }
    }

    /// Land on the current season, re-running once progress arrives, until the user takes over
    private func autoSelect() {
        guard !didUserSelect, let season = defaultSeason, season.id != selected?.id else { return }
        select(season)
        scrollTarget = season.id
    }

    private func select(_ season: SeasonSummary) {
        selected = season
        loadTask?.cancel()
        if let cached = episodesBySeason[season.id] {
            episodes = cached
            isLoading = false
            return
        }
        loadTask = Task { await loadEpisodes(season) }
    }

    private func loadEpisodes(_ season: SeasonSummary) async {
        guard let apiClient else { return }
        isLoading = true
        let loaded = (try? await apiClient.seasonDetails(showId: showId, season: season.number).episodes) ?? []
        // A newer selection may have superseded this load; only the current one wins
        guard !Task.isCancelled, selected?.id == season.id else { return }
        if !loaded.isEmpty {
            episodesBySeason[season.id] = loaded
        }
        episodes = loaded
        isLoading = false
    }
}

private struct EpisodeRow: View {
    /// Fixed row height so the scroll-disabled List can be sized to its contents
    static let height: CGFloat = 58

    let showId: Int
    let seasonNumber: Int
    let episode: EpisodeSummary
    let isWatched: Bool
    let onToggle: (Bool) async -> Void
    @Environment(\.presentEpisode) private var presentEpisode

    var body: some View {
        Button {
            presentEpisode(showId, seasonNumber, episode.number)
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .frame(height: Self.height)
        .listRowInsets(EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 15))
        .listRowBackground(Color.biingeCard)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await onToggle(!isWatched) }
            } label: {
                Label(isWatched ? "Remove" : "Watched",
                      systemImage: isWatched ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(isWatched ? Color.biingeGraniteGray : Color.biingePrimary)
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                Text("\(episode.number)")
                    .font(.biingeCaption1).foregroundStyle(Color.biingeGraniteGray)
                Image(systemName: isWatched ? "checkmark" : "circle.fill")
                    .font(.system(size: isWatched ? 13 : 8))
                    .foregroundStyle(isWatched ? Color.biingeGraniteGray : Color.biingePrimary)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .font(.biingeSubhead).foregroundStyle(.primary)
                    .lineLimit(1)
                Text(episodeMeta)
                    .font(.biingeCaption2).foregroundStyle(Color.biingeSpanishGray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let rating = episode.rating, rating > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Color.biingePrimary)
                    Text(String(format: "%.1f", rating)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var episodeMeta: String {
        var parts: [String] = []
        if let airDate = episode.airDate, !airDate.isEmpty {
            parts.append(formatDate(airDate))
        }
        if episode.runtime > 0 {
            parts.append(formatRuntime(episode.runtime))
        }
        return parts.joined(separator: " · ")
    }

    private func formatDate(_ raw: String) -> String {
        guard raw.count >= 10 else { return raw }
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return raw }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    private func formatRuntime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h\(minutes % 60)m" : "\(minutes)m"
    }
}
