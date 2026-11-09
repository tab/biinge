import JellyfinAPI
import SwiftUI

/// Mac movie details from biinge: the blurred backdrop, poster, the kind and quality badges, title, meta, stored progress, the white pill, list button and More, and overview, then the facts, cast and crew, similar titles and recommendations
struct DesktopMovieDetailsView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// The movie's TMDB ID
    let id: Int
    /// The Jellyfin poster of the tile the details opened from, shown in place of the TMDB poster (nil for the TMDB poster)
    var libraryPoster: URL?

    @State private var details: MovieDetails?
    /// The movie's Jellyfin item for its stored position, nil until it loads and when the library holds none
    @State private var item: BaseItemDto?
    /// The first load's error message, nil once the details are on screen
    @State private var failure: String?
    /// The confirmation of the last list or pin change, nil when none shows
    @State private var toast: Toast?
    /// Set while the list menu shows under the list button
    @State private var isListMenuOpen = false
    /// Set while the page skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(MovieStore.self) private var store
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.macIsCovered) private var isCovered

    var body: some View {
        Group {
            if !isSkeletonHeld, let details {
                // the page fades in as the skeleton leaves, and the swap animates nothing else
                page(details)
                    .macListMenu(isPresented: $isListMenuOpen) { listMenu(details) }
                    // search and the player overlay the stack, and hidden buttons still take key equivalents under them
                    .background { listMenu(details).shortcuts.disabled(isCovered) }
                    .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else if !isSkeletonHeld, let failure {
                ContentUnavailableView {
                    Label("Can’t reach Biinge", systemImage: "icloud.slash")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Retry") {
                        self.failure = nil
                        Task { await load() }
                    }
                }
                .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else {
                DetailsSkeleton(posterWidth: 290, isHeld: $isSkeletonHeld)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .navigationTitle(details?.title ?? "")
        .toast($toast)
        .task { await load() }
        // back from the player, once its stop report has gone out, the progress and button show the new position
        .onChange(of: connection.playbackEnded) {
            Task { await loadItem() }
        }
    }

    private func page(_ details: MovieDetails) -> some View {
        let title = details.title
        let position = item?.userData?.playbackPositionTicks ?? 0
        let runtime = item?.runTimeTicks ?? (details.runtime ?? 0) * 600_000_000
        let meta = [DetailFact.release(details.releaseDate) ?? "", runtime > 0 ? duration(ticks: runtime) : "", details.genres.prefix(3).joined(separator: ", ")]
        let poster = Config.tmdbImageURL(path: details.posterPath, size: "w780")
        let play = DetailsPlay(jellyfinID: details.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 48) {
                    // the slot stays clear until the poster grows in, so the backdrop shows through
                    PosterImage(title: title, cornerRadius: 0, poster: libraryPoster ?? poster, frame: CGSize(width: 290, height: 435), titleFont: .system(size: 14), titlePadding: 12)
                        .environment(\.imageLoadsClear, true)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.biingeText.opacity(0.1), lineWidth: 1))
                        .detailWatchedBadge(store.currentState(id: id) == .watched)
                        .shadow(color: Color.biingeShadow.opacity(0.55), radius: 40, y: 34)
                        .macMorphTarget(.movie(id))
                    // the text arrives 60 ms apart as the clicked poster grows into place
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 8) {
                            Text("Movie")
                                .font(.system(size: 15, weight: .semibold))
                                .opacity(0.75)
                                .padding(.trailing, 4)
                            DesktopQualityBadges(badges: DetailFact.badges(item: item, play: play))
                        }
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
                        if position > 0 {
                            HStack(spacing: 14) {
                                Capsule()
                                    .fill(Color.biingeText.opacity(0.22))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color.biingeText).frame(width: 240 * min(Double(position) / Double(max(runtime, 1)), 1))
                                    }
                                    .frame(width: 240, height: 4)
                                Text("Stopped at \(duration(ticks: position)) · \(duration(ticks: max(runtime - position, 0))) left")
                                    .font(.system(size: 14.5))
                                    .opacity(0.75)
                            }
                            .entrance(after: 0.12)
                        }
                        actions(details, position: position, runtime: runtime)
                            .entrance(after: 0.12)
                        Text(details.overview)
                            .font(.system(size: 18))
                            .lineSpacing(5)
                            .opacity(0.82)
                            .frame(maxWidth: 680, alignment: .leading)
                            .entrance(after: 0.18)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 100)
                .padding(.horizontal, 40)
                .padding(.bottom, 80)
                .background(alignment: .top) {
                    // the art blurred and dimmed behind the header, fading into the page at the bottom
                    DetailBackdrop(url: poster, height: nil, blur: 80, bleed: 120, fadeStart: 0.3, topOverlap: 0)
                }
                DetailsRows(
                    connection: connection, apiClient: apiClient, itemID: details.jellyfinID, credits: details.credits,
                    facts: DetailFact.movie(details, item: item, play: play, state: store.currentState(id: id)),
                    recommendations: RecommendationsRow(
                        items: details.recommendations, state: store.currentState(id:),
                        poster: { Config.tmdbImageURL(path: $0.posterPath, size: "w342") },
                        route: { .title(.movie($0.id)) }
                    )
                )
                .entrance(after: 0.24)
            }
        }
    }

    /// The white pill from DetailPrimary, the list button and More, then the note for a movie the library lacks, a missing or unreachable connection, or a play Jellyfin marked played that Watched lacks
    @ViewBuilder
    private func actions(_ details: MovieDetails, position: Int, runtime: Int) -> some View {
        let play = DetailsPlay(jellyfinID: details.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
        let state = store.currentState(id: id)
        let server = connection.serverName ?? "server"
        // Jellyfin's played mark doesn't reach biinge's Watched by itself
        let playedOnServer = item?.userData?.isPlayed == true
        let primary = DetailPrimary.movie(play: play, state: state, position: position, runtime: runtime, playedOnServer: playedOnServer)
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
            ListButton(pill: DetailListPill(.movie, state: state, isPinned: store.isPinned(id: id)), isOpen: $isListMenuOpen)
            // Start Over needs a stored position the server can play from
            let startOver: (label: String, play: () -> Void)? = if case .play = play, let item, position > 0 {
                ("Start Over", { Task { await connection.play(item, fromStart: true) } })
            } else {
                nil
            }
            MoreMenu(kind: .movie, id: id, apiClient: apiClient, startOver: startOver, markSeason: nil)
        }
        .animation(MotionCurve.exit.animation(MotionDuration.quick), value: primary == nil)
        if let note = PlayNote(play: play, server: connection.serverName, playedUnwatched: playedOnServer && state != .watched) {
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

    /// The list menu under the list button, which closes on a pick and confirms it with a toast
    private func listMenu(_ details: MovieDetails) -> ListMenu {
        let state = store.currentState(id: id)
        let close = { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { isListMenuOpen = false } }
        return ListMenu(kind: .movie, state: state, isPinned: store.isPinned(id: id), server: connection.serverName ?? "server") { target in
            close()
            change(details, to: target)
        } togglePin: {
            close()
            let pinned = !store.isPinned(id: id)
            Task { await store.setPinned(id: id, pinned: pinned) }
            toast = Toast(pinned: pinned)
        } remove: {
            close()
            change(details, to: nil)
        }
    }

    /// Moves the movie to `target`, or removes it for nil, and confirms the change
    private func change(_ details: MovieDetails, to target: WatchState?) {
        Task {
            guard let change = await store.change(
                id: id, title: details.title, posterPath: details.posterPath, runtime: details.runtime ?? 0, jellyfinID: details.jellyfinID,
                to: target, connection: connection
            ) else { return }
            toast = change.toast
            if let failure = await change.outcome.value { toast = failure }
        }
    }

    /// Loads the movie from biinge, then its Jellyfin item; only a failed first load shows the offline state
    private func load() async {
        do {
            let loaded = try await apiClient.movieDetails(id: id)
            details = loaded
            failure = nil
            store.refreshMetadata(id: id, title: loaded.title, posterPath: loaded.posterPath)
        } catch {
            // leaving the screen cancels the load, which is no failure
            guard !Task.isCancelled else { return }
            if details == nil { failure = error.localizedDescription }
            return
        }
        await loadItem()
    }

    /// Loads the movie's Jellyfin item for its stored position; a revoked token disconnects, and any other failure leaves Play without Resume
    private func loadItem() async {
        guard let jellyfinID = details?.jellyfinID, let service = connection.service else { return }
        do {
            item = try await service.item(id: jellyfinID)
        } catch {
            guard !Task.isCancelled else { return }
            _ = await connection.handleFailure(error)
        }
    }
}
