import SwiftUI

struct TvDetailView: View {
    let seriesId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(TvStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.presentSeries) private var presentSeries

    @State private var details: SeriesDetails?
    @State private var progress: WatchProgress?
    @State private var isLoading = true
    @State private var showMenu = false

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
                        ProgressView().tint(Color.biingePrimary)
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
            .background(Color.biingeCard)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
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
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            presentSeries(item.id)
                        } label: {
                            PosterImage(path: item.posterPath, title: item.title, size: "w185").frame(width: 120)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
            }
        }
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
        async let detail = try? await apiClient.seriesDetails(id: seriesId)
        async let prog = try? await apiClient.progress(showId: seriesId)
        details = await detail
        progress = await prog
        isLoading = false
    }

    private func handleMenu(_ action: TvActionMenu.MenuAction, _ series: SeriesDetails) async {
        switch action {
        case .toggle(let target):
            await store.toggle(
                id: seriesId, title: series.title, posterPath: series.posterPath,
                seasonsCount: series.seasonsCount ?? 0, episodesCount: series.episodesCount ?? 0,
                status: series.status ?? "", target: target
            )
        case .pin:
            await store.setPinned(id: seriesId, pinned: true)
        case .unpin:
            await store.setPinned(id: seriesId, pinned: false)
        }
    }

    private func markEpisode(season: SeasonSummary, episode: EpisodeSummary, watched: Bool) async {
        guard let apiClient, let details else { return }
        let series = ProgressSeries(
            title: details.title,
            posterPath: details.posterPath,
            seasonsCount: details.seasonsCount ?? 0,
            episodesCount: details.episodesCount ?? 0,
            status: details.status ?? ""
        )
        do {
            let updated: WatchProgress
            if watched {
                let body = MarkEpisodeBody(
                    series: series,
                    season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                    episode: ProgressEpisodeMeta(title: episode.title, posterPath: episode.posterPath, runtime: episode.runtime, airDate: episode.airDate ?? "")
                )
                updated = try await apiClient.markEpisode(showId: seriesId, seasonId: season.id, episodeId: episode.id, body)
            } else {
                updated = try await apiClient.unmarkEpisode(showId: seriesId, seasonId: season.id, episodeId: episode.id)
            }
            progress = updated
            store.invalidate()
        } catch {
            // keep the last known progress
        }
    }

    private func markSeason(_ season: SeasonSummary, _ episodes: [EpisodeSummary], _ watched: Bool) async {
        guard let apiClient, let details else { return }
        let series = ProgressSeries(
            title: details.title,
            posterPath: details.posterPath,
            seasonsCount: details.seasonsCount ?? 0,
            episodesCount: details.episodesCount ?? 0,
            status: details.status ?? ""
        )
        do {
            let updated: WatchProgress
            if watched {
                let body = MarkSeasonBody(
                    series: series,
                    season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                    episodes: episodes.map {
                        ProgressEpisode(id: $0.id, title: $0.title, posterPath: $0.posterPath, runtime: $0.runtime, airDate: $0.airDate ?? "")
                    }
                )
                updated = try await apiClient.markSeason(showId: seriesId, seasonId: season.id, body)
            } else {
                updated = try await apiClient.unmarkSeason(showId: seriesId, seasonId: season.id)
            }
            progress = updated
            store.invalidate()
        } catch {
            // keep the last known progress
        }
    }
}

/// The action row on a series: two white pills (Want + Watching/Watched) when
/// the show isn't tracked, or a single accent state pill (opening the action
/// menu) when it is.
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
                        .background(Color.biingePrimary, in: Capsule())
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
                seasonsCount: details.seasonsCount ?? 0, episodesCount: details.episodesCount ?? 0,
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

/// The action menu shown when tapping a tracked show's state pill.
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

                VStack(spacing: 2) {
                    ForEach(options, id: \.title) { option in
                        Button(action: option.action) {
                            Text(option.title)
                                .font(.biingeBody).fontWeight(.semibold)
                                .foregroundStyle(Color.biingeGraniteGray)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.biingeBody).fontWeight(.semibold)
                            .foregroundStyle(Color.biingeGraniteGray)
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

/// Horizontal season selector + the selected season's episode list + a
/// mark-whole-season action, matching the RN app.
private struct SeasonsView: View {
    let seasons: [SeasonSummary]
    let showId: Int
    let watchedEpisodeIds: Set<Int>
    let watchedSeasonIds: Set<Int>
    let onMarkEpisode: (SeasonSummary, EpisodeSummary, Bool) async -> Void
    let onMarkSeason: (SeasonSummary, [EpisodeSummary], Bool) async -> Void

    @Environment(\.apiClient) private var apiClient
    @State private var selected: SeasonSummary?
    @State private var episodes: [EpisodeSummary] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        let isActive = selected?.id == season.id
                        Button {
                            select(season)
                        } label: {
                            Text(season.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isActive ? .white : Color.biingeGrayDark)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(isActive ? Color(rgb: 0x2B2835) : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
            }

            if isLoading {
                ProgressView().tint(Color.biingePrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                        EpisodeRow(
                            showId: showId,
                            seasonNumber: selected?.number ?? 0,
                            index: index,
                            episode: episode,
                            isWatched: watchedEpisodeIds.contains(episode.id),
                            showsDivider: index > 0
                        ) { watched in
                            if let season = selected {
                                await onMarkEpisode(season, episode, watched)
                            }
                        }
                    }
                }
                .padding(.horizontal, 15)

                if let season = selected, !episodes.isEmpty {
                    let seasonWatched = watchedSeasonIds.contains(season.id)
                    Button {
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
        .task {
            if selected == nil, let first = seasons.first {
                select(first)
            }
        }
    }

    private func select(_ season: SeasonSummary) {
        selected = season
        Task { await loadEpisodes(season) }
    }

    private func loadEpisodes(_ season: SeasonSummary) async {
        guard let apiClient else { return }
        isLoading = true
        episodes = (try? await apiClient.seasonDetails(showId: showId, season: season.number).episodes) ?? []
        isLoading = false
    }
}

private struct EpisodeRow: View {
    let showId: Int
    let seasonNumber: Int
    let index: Int
    let episode: EpisodeSummary
    let isWatched: Bool
    let showsDivider: Bool
    let onToggle: (Bool) async -> Void
    @Environment(\.presentEpisode) private var presentEpisode
    @State private var dragX: CGFloat = 0

    private let revealWidth: CGFloat = 78
    private let triggerThreshold: CGFloat = 62

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Divider()
            }
            ZStack(alignment: .leading) {
                swipeActionStrip
                rowContent
                    .background(Color.biingeBackground)
                    .offset(x: max(dragX, 0))
                    .simultaneousGesture(swipeGesture)
            }
            .clipped()
        }
    }

    // Leading strip revealed while swiping right — its color and icon preview the
    // pending toggle (mark watched vs. remove), matching the RN swipe-to-toggle.
    private var swipeActionStrip: some View {
        HStack(spacing: 0) {
            Image(systemName: isWatched ? "arrow.uturn.backward" : "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.leading, 24)
                .opacity(dragX > 10 ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isWatched ? Color.biingeGraniteGray : Color.biingePrimary)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.biingeCaption1).foregroundStyle(Color.biingeGraniteGray)
                Image(systemName: isWatched ? "checkmark" : "circle.fill")
                    .font(.system(size: isWatched ? 13 : 8))
                    .foregroundStyle(isWatched ? Color.biingeGraniteGray : Color.biingePrimary)
                    .frame(width: 16)
            }

            Button {
                presentEpisode(showId, seasonNumber, episode.number)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.biingeSubhead).foregroundStyle(.primary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(episodeMeta)
                        .font(.biingeCaption2).foregroundStyle(Color.biingeSpanishGray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let rating = episode.rating, rating > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Color.biingePrimary)
                    Text(String(format: "%.1f", rating)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // Horizontal, rightward swipe toggles watched. `simultaneousGesture` keeps the
    // parent ScrollView's vertical scrolling intact; the height check ignores
    // vertical-dominant drags so scrolling never trips the toggle.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                let horizontal = value.translation.width
                if horizontal > 0 && abs(horizontal) > abs(value.translation.height) {
                    dragX = min(horizontal, revealWidth)
                }
            }
            .onEnded { value in
                let horizontalIntent = abs(value.translation.width) > abs(value.translation.height)
                if horizontalIntent && value.translation.width > triggerThreshold {
                    Task { await onToggle(!isWatched) }
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    dragX = 0
                }
            }
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
