import JellyfinAPI
import SwiftUI

struct MobileMovieDetailsView: View {
    let movieId: Int
    /// The Jellyfin poster of the tile the details opened from, shown in place of the TMDB poster (nil for the TMDB poster)
    var libraryPoster: URL?
    @Environment(\.apiClient) private var apiClient
    @Environment(MovieStore.self) private var store
    /// Nil until the shell puts the connection in the environment, which reads as not connected
    @Environment(JellyfinConnection.self) private var connection: JellyfinConnection?
    @Environment(\.openURL) private var openURL
    @Environment(\.presentMovie) private var presentMovie

    @State private var details: MovieDetails?
    /// The movie's Jellyfin item for its stored position and played mark, nil until it loads and when the library holds none
    @State private var item: BaseItemDto?
    @State private var isLoading = true
    /// Shows the Lists sheet
    @State private var showsLists = false
    /// Shows the More sheet
    @State private var showsMore = false
    /// Shows Connect Jellyfin over the details
    @State private var showsConnect = false
    /// Bumped when a state change lands, so the haptic fires with the UI rather than on the tap
    @State private var stateChanges = 0
    /// Bumped on the lighter commit: pinning and unpinning
    @State private var marks = 0
    /// The confirmation of the last list change, nil when none shows
    @State private var toast: Toast?
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                if !isSkeletonHeld, let details {
                    // the content fades in as the skeleton leaves, and the swap animates nothing else
                    content(details)
                        .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
                } else if isSkeletonHeld || isLoading {
                    DetailSkeleton(isHeld: $isSkeletonHeld)
                } else {
                    DetailLoadError()
                        .transition(.opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)))
                }
            }
            .scrollIndicators(.hidden)

            CloseButton()
            if details != nil {
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
            if let details { moreSheet(details) }
        }
        .detailPlayFailureAlert(connection)
        // the API matches the Jellyfin item for the connected account, so a new connection fetches the details again
        .task(id: connection?.userID) { await load() }
        // the stored position and played mark, again after a connect and once a stopped play's report has gone out
        .task(id: "\(details?.jellyfinID ?? "")-\(connection?.isConnected == true)-\(connection?.playbackEnded ?? 0)") { await loadItem() }
        .sensoryFeedback(.success, trigger: stateChanges)
        .sensoryFeedback(.impact(weight: .light), trigger: marks)
        .toast($toast)
    }

    private func content(_ movie: MovieDetails) -> some View {
        let position = item?.userData?.playbackPositionTicks ?? 0
        let runtime = item?.runTimeTicks ?? (movie.runtime ?? 0) * 600_000_000
        let meta = [DetailFact.release(movie.releaseDate) ?? "", runtime > 0 ? duration(ticks: runtime) : "", movie.genres.prefix(2).joined(separator: ", ")]
        return VStack(alignment: .leading, spacing: 32) {
            // the slot stays clear until the poster grows in, so the backdrop shows through
            PosterImage(path: movie.posterPath, title: movie.title, size: "w500", cornerRadius: 14, poster: libraryPoster)
                .environment(\.imageLoadsClear, true)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.biingeFill(0.1), lineWidth: 1))
                .detailWatchedBadge(store.currentState(id: movieId) == .watched)
                .frame(width: 216)
                .shadow(color: Color.biingeShadow.opacity(0.55), radius: 35, y: 30)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                // the text arrives 60 ms apart as the sheet grows out of the poster
                let kind = Text("Movie")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.biingeText.opacity(0.75))
                let badges = DetailFact.badges(item: item, play: jellyfinPlay(movie))
                // on one row while they fit, so a large text size doesn't break the word
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        kind
                            .padding(.trailing, 2)
                        MobileQualityBadges(badges: badges)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        kind
                        HStack(spacing: 8) {
                            MobileQualityBadges(badges: badges)
                        }
                    }
                }
                .entrance()
                Text(movie.title)
                    .font(.biingeLargeTitle)
                    .tracking(-1.2)
                    .entrance()
                HStack(spacing: 12) {
                    Text(meta.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(Color.biingeText.opacity(0.8))
                    if let rating = movie.rating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .labelStyle(RatingLabelStyle())
                    }
                }
                .font(.subheadline)
                .entrance(after: 0.06)
                if position > 0, runtime > 0 {
                    DetailProgress(fraction: Double(position) / Double(runtime), caption: "\(duration(ticks: max(runtime - position, 0))) left")
                        .entrance(after: 0.12)
                }
                actions(movie, position: position)
                    .padding(.top, 4)
                    .entrance(after: 0.12)
                if !movie.overview.isEmpty {
                    Text(movie.overview)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(Color.biingeText.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .entrance(after: 0.18)
                }
            }
            .padding(.horizontal, 16)

            MobileDetailFacts(facts: DetailFact.movie(movie, item: item, play: jellyfinPlay(movie), state: store.currentState(id: movieId)))
                .padding(.horizontal, 16)
                .entrance(after: 0.24)
            if !movie.credits.isEmpty {
                DetailSection(title: "Cast & Crew") { CreditsRow(credits: movie.credits) }
                    .entrance(after: 0.24)
            }
            if !movie.recommendations.isEmpty {
                DetailSection(title: "Recommendations") { recommendationsRow(movie.recommendations) }
                    .entrance(after: 0.24)
            }
        }
        .padding(.top, 72)
        .padding(.bottom, 48)
        // pinned to the scroll view's width, because a page answering a pixel wider pans sideways
        .containerRelativeFrame(.horizontal, alignment: .leading)
        .background(alignment: .top) {
            DetailBackdrop(url: Config.tmdbImageURL(path: movie.posterPath, size: "w780"))
        }
    }

    /// The white pill of the next step beside the list pill, then the note on what keeps it from playing or the played mark biinge lacks
    @ViewBuilder
    private func actions(_ movie: MovieDetails, position: Int) -> some View {
        let play = jellyfinPlay(movie)
        let state = store.currentState(id: movieId)
        let server = connection?.serverName ?? "server"
        let isPlayed = item?.userData?.isPlayed == true
        let runtime = item?.runTimeTicks ?? (movie.runtime ?? 0) * 600_000_000
        let primary = DetailPrimary.movie(play: play, state: state, position: position, runtime: runtime, playedOnServer: isPlayed)
        // the progress line above already says the time left
        DetailActionRow(primary: primary, connection: connection) { change(movie, to: $0) } secondary: {
            DetailListButton(pill: DetailListPill(.movie, state: state, isPinned: store.isPinned(id: movieId)), fills: primary == nil) {
                showsLists = true
            }
        }
        if let note = PlayNote(play: play, server: connection?.serverName, playedUnwatched: isPlayed && state != .watched) {
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
                DetailNote(text: note.text, systemImage: note.systemImage, cta: "Add to Watched") { change(movie, to: .watched) }
            case .notOnServer, .seasonNotOnServer, .airs:
                DetailNote(text: note.text, systemImage: note.systemImage)
            }
        }
    }

    /// The Lists sheet: Want to Watch and Watched, Pin in Want, and Remove
    private func listsSheet(_ movie: MovieDetails) -> some View {
        DetailListsSheet(
            kind: .movie, title: movie.title, server: connection?.serverName ?? "Jellyfin",
            state: store.currentState(id: movieId), isPinned: store.isPinned(id: movieId)
        ) { target in
            showsLists = false
            change(movie, to: target)
        } pin: { pinned in
            showsLists = false
            Task {
                await store.setPinned(id: movieId, pinned: pinned)
                toast = Toast(pinned: pinned)
                marks += 1
            }
        } remove: {
            showsLists = false
            change(movie, to: nil)
        }
    }

    /// The More sheet: Start Over once started on the server, Watch Trailer and Share
    private func moreSheet(_ movie: MovieDetails) -> some View {
        DetailMenuSheet(title: "More", subtitle: movie.title) {
            if let connection, case .play(let jellyfinID) = jellyfinPlay(movie), item?.userData?.playbackPositionTicks ?? 0 > 0 {
                DetailStartOverRow(title: "Start Over", connection: connection, jellyfinID: jellyfinID) { showsMore = false }
            }
            if let trailer = trailerURL(movie) {
                DetailMenuButton(systemImage: "play.rectangle", title: "Watch Trailer") {
                    showsMore = false
                    openURL(trailer)
                }
            }
            DetailShareRow(kind: .movie, id: movieId) { showsMore = false }
        }
    }

    /// What the movie's Jellyfin item offers now: a play, or why it can't play
    private func jellyfinPlay(_ movie: MovieDetails) -> DetailsPlay {
        DetailsPlay(jellyfinID: movie.jellyfinID, isConnected: connection?.isConnected == true, isUnreachable: connection?.isUnreachable == true)
    }

    /// The movie's YouTube trailer, nil when it has none
    private func trailerURL(_ movie: MovieDetails) -> URL? {
        movie.videos.first.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.key)") }
    }

    private func recommendationsRow(_ items: [Recommendation]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        presentMovie(item.id)
                    } label: {
                        PosterImage(path: item.posterPath, title: item.title, size: "w342", cornerRadius: 10).frame(width: 112)
                            .trackedBadge(.movie(item.id))
                    }
                    .buttonStyle(.pressable)
                    .detailTransitionSource("movie-\(item.id)")
                }
            }
            .padding(.horizontal)
        }
    }

    /// Moves the movie to `target`, or removes it for nil, and confirms the change
    private func change(_ movie: MovieDetails, to target: WatchState?) {
        Task {
            guard let change = await store.change(
                id: movieId, title: movie.title, posterPath: movie.posterPath, runtime: movie.runtime ?? 0, jellyfinID: movie.jellyfinID,
                to: target, connection: connection
            ) else { return }
            toast = change.toast
            stateChanges += 1
            if let failure = await change.outcome.value { toast = failure }
        }
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        // load the library too — opened from Search, the state pill would read an empty store
        async let libraryLoad: Void = store.loadIfNeeded()
        // a failed refetch keeps the details on screen
        if let fresh = try? await apiClient.movieDetails(id: movieId) { details = fresh }
        isLoading = false
        if let details {
            store.refreshMetadata(id: movieId, title: details.title, posterPath: details.posterPath)
        }
        await libraryLoad
    }

    /// Loads the movie's Jellyfin item for its stored position (cleared while disconnected); a revoked token disconnects, and any other failure leaves Play without Resume
    private func loadItem() async {
        // without a connection the stored position and played mark no longer apply
        guard let jellyfinID = details?.jellyfinID, let connection, let service = connection.service else {
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
}

/// Shared error state for detail screens (e.g. missing TMDB token)
struct DetailLoadError: View {
    /// Runs when Retry is tapped (nil leaves the button out)
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load details", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Please try again.")
        } actions: {
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.glass)
            }
        }
        .padding(.top, 80)
    }
}
