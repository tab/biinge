import JellyfinAPI
import SwiftUI

struct MobileEpisodeDetailsView: View {
    let seriesId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(SeriesStore.self) private var store
    /// Nil until the shell puts the connection in the environment, which reads as not connected
    @Environment(JellyfinConnection.self) private var connection: JellyfinConnection?

    @State private var episode: EpisodeDetails?
    @State private var series: SeriesDetails?
    /// The season's episodes the store's ordered mark needs, nil until they load
    @State private var seasonEpisodes: [EpisodeSummary]?
    /// The episode's Jellyfin item for its stored position, nil until it loads and when the library holds none
    @State private var item: BaseItemDto?
    @State private var isLoading = true
    /// Shows Connect Jellyfin over the details
    @State private var showsConnect = false
    /// The still's width, which sets its 16:9 height
    @State private var stillWidth: CGFloat = 0
    /// The failed mark's message, nil when no alert shows
    @State private var watchedFailure: String?
    /// Bumped when a tick lands, so the haptic fires with the UI rather than on the tap
    @State private var marks = 0
    /// The confirmation of the last Watched tap, nil when none shows
    @State private var toast: Toast?
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false

    /// Progress lives in the store, shared with the show detail underneath this sheet
    private var progress: WatchProgress? {
        store.progress(id: seriesId)
    }

    private var season: SeasonSummary? {
        series?.seasons.first { $0.number == seasonNumber }
    }

    /// The episode as the season lists it, which the store's mark takes (nil until the season loads)
    private var summary: EpisodeSummary? {
        seasonEpisodes?.first { $0.number == episodeNumber }
    }

    private var isWatched: Bool {
        guard let episode else { return false }
        // Prefer live store progress (reflects optimistic toggles); fall back to the
        // server-provided flag when the sheet is opened without progress loaded
        if let progress { return progress.watchedEpisodes.contains(episode.id) }
        return episode.watched
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                if !isSkeletonHeld, let episode {
                    // the content fades in as the skeleton leaves, and the swap animates nothing else
                    content(episode)
                        .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
                } else if isSkeletonHeld || isLoading {
                    DetailSkeleton(isEpisode: true, isHeld: $isSkeletonHeld)
                } else {
                    DetailLoadError()
                        .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
                }
            }
            .scrollIndicators(.hidden)

            CloseButton()
        }
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .detailPlayFailureAlert(connection)
        .sheet(isPresented: $showsConnect) {
            if let connection, let apiClient { DetailConnectSheet(connection: connection, apiClient: apiClient) }
        }
        // the API matches the Jellyfin items for the connected account, so a new connection fetches the details again
        .task(id: connection?.userID) { await load() }
        // the stored position, again after a connect and once a stopped play's report has gone out
        .task(id: "\(episode?.jellyfinID ?? "")-\(connection?.isConnected == true)-\(connection?.playbackEnded ?? 0)") { await loadItem() }
        .sensoryFeedback(.impact(weight: .light), trigger: marks)
        .toast($toast)
        .alert(
            "Couldn’t change Watched",
            isPresented: Binding(get: { watchedFailure != nil }, set: { if !$0 { watchedFailure = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(watchedFailure ?? "")
        }
    }

    private func content(_ ep: EpisodeDetails) -> some View {
        let position = item?.userData?.playbackPositionTicks ?? 0
        let runtime = item?.runTimeTicks ?? ep.runtime * 600_000_000
        let share: Double? = position > 0 && runtime > 0 ? Double(position) / Double(runtime) : nil
        let eyebrow = [series?.title ?? "", seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)", "Episode \(ep.number)"]
        let play = DetailsPlay(jellyfinID: ep.jellyfinID, isConnected: connection?.isConnected == true, isUnreachable: connection?.isUnreachable == true)
        let badges = DetailFact.badges(item: item, play: play)
        return VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                // the wide still, fading into the page
                // a fixed 16:9 height, as the scroll view's stack would otherwise squeeze a flexible ratio
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: stillWidth * 9 / 16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stillWidth = $0 }
                    .overlay {
                        // the slot stays clear until the still grows in
                        CachedImage(url: Config.tmdbImageURL(path: ep.posterPath, size: "w780"), maxPixel: 1200) { Color.biingeSecondaryCard }
                            .environment(\.imageLoadsClear, true)
                    }
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [.init(color: Color.biingeBackground.opacity(0), location: 0.55), .init(color: Color.biingeBackground, location: 1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 14) {
                    // the text arrives 60 ms apart under the still
                    let kind = Text(eyebrow.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.biingeText.opacity(0.75))
                    // the line and the badges keep together, on one row while they fit, so a long series name wraps only itself
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            kind
                                .padding(.trailing, 2)
                            MobileQualityBadges(badges: badges)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            kind
                            if !badges.isEmpty {
                                HStack(spacing: 8) {
                                    MobileQualityBadges(badges: badges)
                                }
                            }
                        }
                    }
                    .entrance()
                    Text(ep.title)
                        .font(.biingeTitle1)
                        .tracking(-0.8)
                        .entrance()
                    HStack(spacing: 12) {
                        // the facts below carry the air date
                        if runtime > 0 {
                            Text(duration(ticks: runtime))
                                .foregroundStyle(Color.biingeText.opacity(0.8))
                        }
                        if let rating = ep.rating, rating > 0 {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .labelStyle(RatingLabelStyle())
                        }
                    }
                    .font(.subheadline)
                    .entrance(after: 0.06)
                    if let share {
                        DetailProgress(fraction: share, caption: "\(duration(ticks: max(runtime - position, 0))) left")
                            .entrance(after: 0.12)
                    }
                    actions(ep, share: share)
                        .padding(.top, 4)
                        .entrance(after: 0.12)
                    if !ep.overview.isEmpty {
                        Text(ep.overview)
                            .font(.body)
                            .lineSpacing(3)
                            .foregroundStyle(Color.biingeText.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .entrance(after: 0.18)
                    }
                    MobileDetailFacts(facts: DetailFact.episode(ep, creators: series?.creators, item: item, play: play), topPadding: 18)
                        .padding(.top, 4)
                        .entrance(after: 0.24)
                }
                .padding(.horizontal, 16)
            }

            if !ep.credits.isEmpty {
                DetailSection(title: "Cast & Crew") { CreditsRow(credits: ep.credits) }
                    .entrance(after: 0.24)
            }
        }
        .padding(.bottom, 48)
        // pinned to the scroll view's width, because a page answering a pixel wider pans sideways
        .containerRelativeFrame(.horizontal, alignment: .leading)
    }

    /// Play, Resume or Play Again of the episode's own Jellyfin item beside Mark Watched or Mark Unwatched (Mark alone fills the row off the server), then the note on what keeps it from playing
    @ViewBuilder
    private func actions(_ ep: EpisodeDetails, share: Double?) -> some View {
        let play = DetailsPlay(jellyfinID: ep.jellyfinID, isConnected: connection?.isConnected == true, isUnreachable: connection?.isUnreachable == true)
        let server = connection?.serverName ?? "server"
        let label = share != nil ? "Resume" : isWatched ? "Play Again" : "Play"
        let systemImage = share == nil && isWatched ? "arrow.counterclockwise" : "play.fill"
        let primary: DetailPrimary? = switch play {
        case .play(let jellyfinID): DetailPrimary(label: label, detail: nil, systemImage: systemImage, action: .play(jellyfinID))
        case .unreachable: DetailPrimary(label: label, detail: nil, systemImage: systemImage, action: .unreachable)
        case .connect, .notOnServer: nil
        }
        DetailActionRow(primary: primary, connection: connection) {
            // the store's mark needs the season; a failed season load still shows Mark, and the tap loads it again
            if season != nil {
                Button(action: toggleWatched) {
                    HStack(spacing: 6) {
                        Image(systemName: isWatched ? "checkmark.circle.badge.xmark" : "checkmark")
                            .font(.system(size: 17, weight: .medium))
                            .iconPop(isWatched)
                            .accessibilityHidden(true)
                        Text(isWatched ? "Mark Unwatched" : "Mark Watched")
                            .lineLimit(1)
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.biingeText)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.biingeFill(0.14), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        if let note = PlayNote(play: play, server: connection?.serverName) {
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
            case .notOnServer, .playedUnwatched, .seasonNotOnServer, .airs:
                DetailNote(text: note.text, systemImage: note.systemImage)
            }
        }
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        async let libraryLoad: Void = store.loadIfNeeded()
        async let episodeResult = try? await apiClient.episodeDetails(seriesId: seriesId, season: seasonNumber, episode: episodeNumber)
        async let seriesResult = try? await apiClient.seriesDetails(id: seriesId)
        async let seasonResult = try? await apiClient.seasonDetails(seriesId: seriesId, season: seasonNumber)
        // a failed refetch keeps what an earlier load brought
        episode = await episodeResult ?? episode
        series = await seriesResult ?? series
        seasonEpisodes = await seasonResult?.episodes ?? seasonEpisodes
        isLoading = false
        await libraryLoad
        // The episode payload carries its own watched flag, so only fetch progress to
        // seed the store when it isn't already loaded (e.g. opened via deep link)
        guard series != nil, store.progress(id: seriesId) == nil else { return }
        let started = store.episodeMarks[seriesId]
        // an episode mark made while the read was in flight is newer, so the read gives way to it
        if let fetched = try? await apiClient.progress(seriesId: seriesId), started == store.episodeMarks[seriesId] {
            setProgress(fetched)
        }
    }

    /// Loads the episode's Jellyfin item for its stored position (cleared while disconnected); a revoked token disconnects, and any other failure leaves Play without Resume
    private func loadItem() async {
        // without a connection the stored position no longer applies
        guard let jellyfinID = episode?.jellyfinID, let connection, let service = connection.service else {
            item = nil
            return
        }
        do {
            item = try await service.item(id: jellyfinID)
        } catch {
            guard !Task.isCancelled else { return }
            _ = await connection.handleFailure(error)
        }
    }

    /// Marks or unmarks the episode through the store, which orders it with the series screen's marks (a failure, a failed season load included, shows the alert)
    private func toggleWatched() {
        guard let apiClient, let series, let season else { return }
        let watched = !isWatched
        marks += 1
        Task {
            // the store's mark needs the season's episodes, so a load that failed with the sheet's runs again here
            if seasonEpisodes == nil {
                seasonEpisodes = try? await apiClient.seasonDetails(seriesId: seriesId, season: seasonNumber).episodes
            }
            guard let seasonEpisodes, let summary else {
                watchedFailure = "Nothing changed. Couldn’t load this season."
                return
            }
            // Home hides a marked episode at once, as Jellyfin may still report it unplayed, then follows the store's progress once the write ends
            if let jellyfinID = summary.jellyfinID { connection?.setWatched(itemID: jellyfinID, watched: watched) }
            let confirmation = Toast(
                message: "S\(seasonNumber) · E\(episodeNumber) marked \(watched ? "watched" : "unwatched")",
                systemImage: watched ? "checkmark.circle.fill" : nil
            )
            toast = confirmation
            do {
                try await store.setEpisodeWatched(watched, episode: summary, season: season, seasonEpisodes: seasonEpisodes, details: series)
            } catch {
                // the alert says nothing changed, so its confirmation goes unless a later tap replaced it
                if toast == confirmation { toast = nil }
                watchedFailure = "Nothing changed. \(error.localizedDescription)"
            }
            if let jellyfinID = summary.jellyfinID {
                connection?.setWatched(itemID: jellyfinID, watched: store.progress(id: seriesId)?.watchedEpisodes.contains(summary.id) ?? false)
            }
        }
    }

    /// Seeds the store with the fetched progress, shared with the show detail underneath and the grid
    private func setProgress(_ value: WatchProgress) {
        guard let series else { return }
        store.apply(
            value, id: seriesId,
            title: series.title, posterPath: series.posterPath,
            episodesCount: series.totalEpisodesCount, pinned: series.pinned
        )
    }
}
