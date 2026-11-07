import JellyfinAPI
import SwiftUI

/// Apple TV episode details from biinge: the series, season, episode and quality badges, title, runtime, air date and rating, the resume progress, Play, Resume or Play Again and the watched mark, the full synopsis and the facts beside the wide still
struct TVEpisodeDetailsView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// The series' TMDB ID
    let seriesID: Int
    let seasonNumber: Int
    let episodeNumber: Int

    @State private var details: SeriesDetails?
    @State private var season: SeasonDetails?
    /// The episode's details for its facts, nil until they load and when the load fails, which leaves the facts out
    @State private var episodeDetails: EpisodeDetails?
    /// The episode's Jellyfin item for its stored position, nil until it loads and when the library holds none
    @State private var item: BaseItemDto?
    /// The load's error message, nil once the episode is on screen
    @State private var failure: String?
    /// The failed Watched write's message, nil when no alert shows
    @State private var watchedFailure: String?
    /// The confirmation of the last Watched press, nil when none shows
    @State private var toast: Toast?
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(SeriesStore.self) private var store
    @Environment(\.attemptPlay) private var attemptPlay
    @FocusState private var isPrimaryFocused: Bool

    private var episode: EpisodeSummary? {
        season?.episodes.first { $0.number == episodeNumber }
    }

    var body: some View {
        Group {
            if !isSkeletonHeld, let details, let season, let episode {
                // the page fades in as the skeleton leaves, and the swap animates nothing else
                page(details, season: season, episode: episode)
                    .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else if !isSkeletonHeld, let failure {
                Message(icon: "icloud.slash", title: "Can’t reach Biinge", text: failure, action: "Try Again") {
                    self.failure = nil
                    Task { await load() }
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
                if !isSkeletonHeld, let episode {
                    TVBackdropArt(url: Config.tmdbImageURL(path: episode.posterPath, size: "w780"))
                        .backdropFade()
                }
                LinearGradient(
                    stops: [.init(color: Color.biingeBackground.opacity(0.85), location: 0), .init(color: Color.biingeBackground.opacity(0.2), location: 0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .ignoresSafeArea()
        }
        .alert(
            "Couldn’t change Watched",
            isPresented: Binding(get: { watchedFailure != nil }, set: { if !$0 { watchedFailure = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(watchedFailure ?? "")
        }
        .defaultFocus($isPrimaryFocused, true)
        .toast($toast)
        .task { await load() }
        .task(id: episode?.jellyfinID) { await loadItem() }
        // back from the player, once its stop report has gone out, the progress and the buttons show the new state
        .onChange(of: connection.playbackEnded) {
            Task { await loadItem() }
        }
    }

    private func page(_ details: SeriesDetails, season: SeasonDetails, episode: EpisodeSummary) -> some View {
        let isWatched = store.progress(id: seriesID).map { $0.watchedEpisodes.contains(episode.id) } ?? episode.watched
        // the item's own position and length, when it has loaded for this episode
        let position = item?.id == episode.jellyfinID ? item?.userData?.playbackPositionTicks ?? 0 : 0
        let runtime = item?.id == episode.jellyfinID ? item?.runTimeTicks ?? episode.runtime * 600_000_000 : episode.runtime * 600_000_000
        let aired = episode.airDate.flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
        // the facts carry the date once they load; it holds no time, so it formats in UTC to keep its day
        let date = episodeDetails == nil ? aired?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)) ?? "" : ""
        let meta = [runtime > 0 ? duration(ticks: runtime) : "", date]
        let play = DetailsPlay(jellyfinID: episode.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
        // holds two rows of facts where the tracks can land, so the centred column doesn't jump
        let factsHeight: CGFloat = if case .play = play { 74 } else { 0 }
        return HStack(alignment: .center, spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Text("\(details.title) · \(seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)") · Episode \(episode.number)")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.biingeText.opacity(0.75))
                        .padding(.trailing, 6)
                    TVQualityBadges(badges: DetailFact.badges(item: item, play: play))
                }
                Text(episode.title)
                    .font(.system(size: episode.title.count > 28 ? 64 : 84, weight: .bold))
                    .tracking((episode.title.count > 28 ? 64 : 84) * -0.035)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 22) {
                    Text(meta.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(Color.biingeText.opacity(0.82))
                    if let rating = episode.rating, rating > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.biingePrimary)
                            Text(rating, format: .number.precision(.fractionLength(1)))
                                .fontWeight(.semibold)
                        }
                    }
                }
                .font(.system(size: 29))
                if position > 0 {
                    HStack(spacing: 20) {
                        Capsule()
                            .fill(Color.biingeText.opacity(0.22))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.biingeText).frame(width: 420 * min(Double(position) / Double(max(runtime, 1)), 1))
                            }
                            .frame(width: 420, height: 8)
                        Text("Stopped at \(duration(ticks: position)) · \(duration(ticks: max(runtime - position, 0))) left")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.biingeText.opacity(0.75))
                    }
                }
                actions(details, season: season, episode: episode, isWatched: isWatched, position: position, runtime: runtime)
                    .padding(.top, 8)
                Text(episode.overview)
                    .font(.system(size: 30))
                    .lineSpacing(7)
                    .foregroundStyle(Color.biingeText.opacity(0.82))
                    .frame(maxWidth: 1000, alignment: .leading)
                if let episodeDetails {
                    TVDetailFacts(facts: DetailFact.episode(episodeDetails, creators: details.creators, item: item, play: play))
                        .frame(minHeight: factsHeight, alignment: .topLeading)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // the slot stays clear until the still grows in
            PosterImage(title: episode.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: episode.posterPath, size: "w780"),
                        frame: CGSize(width: 640, height: 360), titleFont: .system(size: 26), titlePadding: 20)
                .environment(\.imageLoadsClear, true)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.biingeText.opacity(0.12), lineWidth: 1))
                .shadow(color: Color.biingeShadow.opacity(0.6), radius: 45, y: 40)
        }
        .padding(.horizontal, 96)
        .padding(.vertical, 80)
    }

    /// Play, Resume or Play Again beside Mark Watched or Mark Unwatched, then the note on why Play isn't here
    @ViewBuilder
    private func actions(_ details: SeriesDetails, season: SeasonDetails, episode: EpisodeSummary, isWatched: Bool, position: Int, runtime: Int) -> some View {
        let play = DetailsPlay(jellyfinID: episode.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
        let server = connection.serverName ?? "server"
        // an episode plays as a movie does, and never offers a list (nil when it can't play here)
        let primary: DetailPrimary? = switch play {
        case .play, .unreachable: DetailPrimary.movie(play: play, state: isWatched ? .watched : nil, position: position, runtime: runtime, playedOnServer: false)
        case .connect, .notOnServer: nil
        }
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
                    case .move:
                        break
                    }
                } label: {
                    Label(primary.title, systemImage: primary.systemImage ?? "play.fill")
                }
                .buttonStyle(PillButtonStyle(isPrimary: true, isDisabled: primary.action == .unreachable))
                .focused($isPrimaryFocused)
            }
            Button {
                setWatched(!isWatched, episode: episode, seasonEpisodes: season.episodes, details: details)
            } label: {
                Label(isWatched ? "Mark Unwatched" : "Mark Watched", systemImage: isWatched ? "checkmark.circle.badge.xmark" : "checkmark")
            }
            // without a play the mark is the page's only button, so focus lands on it
            .buttonStyle(PillButtonStyle())
        }
        if let note = PlayNote(play: play, server: connection.serverName) {
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

    /// Marks or unmarks the episode through the store, which orders it with every screen's marks (a failure shows the alert)
    private func setWatched(_ watched: Bool, episode: EpisodeSummary, seasonEpisodes: [EpisodeSummary], details: SeriesDetails) {
        // the series lists every season the episode's season loads from
        guard let season = details.seasons.first(where: { $0.number == seasonNumber }) else { return }
        // Home hides a marked episode at once, as Jellyfin may still report it unplayed, then follows the store's progress once the write ends
        if let jellyfinID = episode.jellyfinID { connection.setWatched(itemID: jellyfinID, watched: watched) }
        let confirmation = Toast(episodeWatched: watched)
        toast = confirmation
        Task {
            do {
                try await store.setEpisodeWatched(watched, episode: episode, season: season, seasonEpisodes: seasonEpisodes, details: details)
            } catch {
                // the alert says nothing changed, so its confirmation goes unless a later press replaced it
                if toast == confirmation { toast = nil }
                watchedFailure = "Nothing changed. \(error.localizedDescription)"
            }
            if let jellyfinID = episode.jellyfinID {
                connection.setWatched(itemID: jellyfinID, watched: store.progress(id: seriesID)?.watchedEpisodes.contains(episode.id) ?? false)
            }
        }
    }

    /// Loads the series, for the mark's metadata, the episode's season and its details for the facts from biinge (a failed details load only leaves the facts out)
    private func load() async {
        async let series = apiClient.seriesDetails(id: seriesID)
        async let episodes = apiClient.seasonDetails(seriesId: seriesID, season: seasonNumber)
        async let facts = try? await apiClient.episodeDetails(seriesId: seriesID, season: seasonNumber, episode: episodeNumber)
        // the facts land with the page, so the column doesn't move under them
        episodeDetails = await facts ?? episodeDetails
        do {
            (details, season) = try await (series, episodes)
            failure = nil
        } catch {
            // leaving the screen cancels the load, which is no failure
            guard !Task.isCancelled else { return }
            if details == nil || season == nil { failure = error.localizedDescription }
        }
    }

    /// Loads the episode's Jellyfin item for its stored position; a revoked token disconnects, and any other failure leaves Play without Resume
    private func loadItem() async {
        guard let jellyfinID = episode?.jellyfinID, let service = connection.service else { return }
        do {
            item = try await service.item(id: jellyfinID)
        } catch {
            guard !Task.isCancelled else { return }
            _ = await connection.handleFailure(error)
        }
    }
}

extension TVEpisodeDetailsView {
    /// The loading skeleton in the page's layout: the series line, title, meta, buttons, synopsis and facts beside the wide still where they land
    private var skeleton: some View {
        HStack(alignment: .center, spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 520, height: 28)
                SkeletonBlock(cornerRadius: 12)
                    .frame(width: 640, height: 84)
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 320, height: 29)
                HStack(spacing: 22) {
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 220, height: 76)
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 280, height: 76)
                }
                .padding(.top, 8)
                SkeletonBlock(cornerRadius: 8)
                    .frame(maxWidth: 1000)
                    .frame(height: 150)
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 800, height: 74)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SkeletonBlock(cornerRadius: 24)
                .frame(width: 640, height: 360)
        }
        .padding(.horizontal, 96)
        .padding(.vertical, 80)
        .loadingSkeleton(isHeld: $isSkeletonHeld)
    }
}
