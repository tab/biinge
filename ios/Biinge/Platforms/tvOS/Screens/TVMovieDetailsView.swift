import JellyfinAPI
import SwiftUI

/// Apple TV movie details from biinge: backdrop, badges, title, meta, progress, the next step, list and ••• pills with their menus, overview, facts and poster, then Cast & Crew, Recommendations and More in Your Library
struct TVMovieDetailsView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// The movie's TMDB ID
    let id: Int
    /// The Jellyfin poster of the tile the details opened from, shown in place of the TMDB poster (nil for the TMDB poster)
    var libraryPoster: URL?

    @State private var details: MovieDetails?
    /// The movie's Jellyfin item for its stored position and streams, nil until it loads and when the library holds none
    @State private var item: BaseItemDto?
    /// The first load's error message, nil once the details are on screen
    @State private var failure: String?
    /// The confirmation of the last list change or pin, nil when none shows
    @State private var toast: Toast?
    /// The list menu or More while one shows
    @State private var menu: DetailMenu?
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(MovieStore.self) private var store
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: HomeFocus?

    var body: some View {
        Group {
            if !isSkeletonHeld, let details {
                // the page fades in as the skeleton leaves, and the swap animates nothing else
                page(details)
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
        // the backdrop arrives with the page, after a shown skeleton's hold
        .background { background(isSkeletonHeld ? nil : Config.tmdbImageURL(path: details?.posterPath ?? "", size: "w780")) }
        .defaultFocus($focus, .hero)
        .tvDetailMenu($menu, poster: Config.tmdbImageURL(path: details?.posterPath ?? "", size: "w780"), title: details?.title ?? "", toast: $toast) { shown in
            guard let details else { return [] }
            let position = item?.userData?.playbackPositionTicks ?? 0
            let play = DetailsPlay(jellyfinID: details.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
            return shown == .list ? listRows(details) : moreRows(play: play, position: position)
        }
        .toast($toast)
        .task { await load() }
        // back from the player, once its stop report has gone out, the progress, buttons and posters show the new state
        .onChange(of: connection.playbackEnded) {
            Task { await load() }
        }
    }

    /// The movie's art blurred and dimmed behind the page (Home's hero treatment)
    private func background(_ poster: URL?) -> some View {
        ZStack {
            Color.biingeBackground
            if poster != nil {
                TVBackdropArt(url: poster)
                    .backdropFade()
            }
            LinearGradient(
                stops: [.init(color: Color.biingeBackground.opacity(0.7), location: 0), .init(color: Color.biingeBackground.opacity(0.1), location: 0.75)],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                stops: [.init(color: Color.biingeBackground.opacity(0), location: 0.5), .init(color: Color.biingeBackground, location: 0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func page(_ details: MovieDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(details)
                TVDetailsRows(
                    connection: connection, itemID: details.jellyfinID, credits: details.credits,
                    recommendations: TVRecommendationsRow(
                        items: details.recommendations, state: store.currentState(id:),
                        poster: { Config.tmdbImageURL(path: $0.posterPath, size: "w500") },
                        route: { .title(.movie($0.id)) }
                    )
                )
                .padding(.bottom, 80)
            }
        }
        .ignoresSafeArea()
    }

    /// The first screen: badges, title, meta, progress, buttons, the "Not on" note, overview and facts beside the poster
    private func header(_ details: MovieDetails) -> some View {
        let title = details.title
        let position = item?.userData?.playbackPositionTicks ?? 0
        let runtime = item?.runTimeTicks ?? (details.runtime ?? 0) * 600_000_000
        let meta = [DetailFact.release(details.releaseDate) ?? "", runtime > 0 ? duration(ticks: runtime) : "", details.genres.prefix(3).joined(separator: ", ")]
        let play = DetailsPlay(jellyfinID: details.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)

        return ZStack(alignment: .topLeading) {
            // the slot stays clear until the poster grows in, so the background shows through
            PosterImage(title: title, cornerRadius: 0, poster: libraryPoster ?? Config.tmdbImageURL(path: details.posterPath, size: "w780"),
                        frame: CGSize(width: 440, height: 660), titleFont: .system(size: 26), titlePadding: 20)
                .environment(\.imageLoadsClear, true)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.biingeText.opacity(0.1), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if store.isPinned(id: id) { PinBadge() }
                }
                .detailWatchedBadge(store.currentState(id: id) == .watched)
                .shadow(color: Color.biingeShadow.opacity(0.6), radius: 45, y: 40)
                .padding(.top, 130)
                .padding(.trailing, 120)
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 14) {
                    Text("Movie")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.biingeText.opacity(0.75))
                        .padding(.trailing, 6)
                    TVQualityBadges(badges: DetailFact.badges(item: item, play: play))
                }
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
                actions(details, position: position, runtime: runtime)
                    .padding(.top, 8)
                Text(details.overview)
                    .font(.system(size: 30))
                    .lineSpacing(7)
                    .lineLimit(3)
                    .foregroundStyle(Color.biingeText.opacity(0.82))
                    .frame(maxWidth: 1080, alignment: .leading)
                TVDetailFacts(facts: DetailFact.movie(details, item: item, play: play, state: store.currentState(id: id)))
                    .padding(.top, 4)
            }
            .frame(width: 1160, alignment: .leading)
            .padding(.leading, 96)
            .padding(.top, 190)
            .padding(.bottom, 36)
        }
        // the next row peeks in under a short column and moves down for a long one
        .frame(maxWidth: .infinity, minHeight: 960, alignment: .topLeading)
        .focusSection()
    }

    /// The next step's pill (a play, else Add to Want to Watch), the list pill and •••, then the note on why Play isn't here or that Jellyfin played the movie unmarked
    @ViewBuilder
    private func actions(_ details: MovieDetails, position: Int, runtime: Int) -> some View {
        let play = DetailsPlay(jellyfinID: details.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
        let state = store.currentState(id: id)
        let primary = DetailPrimary.movie(play: play, state: state, position: position, runtime: runtime, playedOnServer: item?.userData?.isPlayed == true)
        let pill = DetailListPill(.movie, state: state, isPinned: store.isPinned(id: id))
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
                .focused($focus, equals: .hero)
                // the add folds the pill away as the list pill takes the list's name
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
            Button { menu = .list } label: {
                ListPillLabel(kind: .movie, pill: pill, isUnlisted: state == nil)
            }
            .buttonStyle(PillButtonStyle(isMenu: true, isPinned: pill.isPinned))
            .focused($focus, equals: primary == nil ? .hero : .card(row: "Actions", id: "List"))
            if !moreRows(play: play, position: position).isEmpty {
                Button { menu = .more } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .buttonStyle(PillButtonStyle(isIconOnly: true))
            }
        }
        .animation(MotionCurve.exit.animation(MotionDuration.quick), value: primary == nil)
        if let note = PlayNote(play: play, server: connection.serverName, playedUnwatched: item?.userData?.isPlayed == true && state != .watched) {
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

    /// The list menu's rows: Want to Watch and Watched, then Pin to Up Next and Remove
    private func listRows(_ details: MovieDetails) -> [MenuRow] {
        MenuRow.lists(
            .movie, server: connection.serverName ?? "server", state: store.currentState(id: id), isPinned: store.isPinned(id: id),
            move: { change(details, to: $0) },
            pin: { pinned in
                Task { await store.setPinned(id: id, pinned: pinned) }
                toast = Toast(pinned: pinned)
            },
            remove: { change(details, to: nil) }
        )
    }

    /// More's rows: Start Over while Jellyfin holds a position and the server answers (empty otherwise, which hides •••)
    private func moreRows(play: DetailsPlay, position: Int) -> [MenuRow] {
        guard case .play = play, position > 0, let item else { return [] }
        return [MenuRow(label: "Start Over", systemImage: "arrow.counterclockwise", summary: "From 0:00") {
            Task { await connection.play(item, fromStart: true) }
        }]
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

    /// Loads the movie's Jellyfin item for its stored position and streams; a revoked token disconnects, and any other failure leaves Play without Resume
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

extension TVMovieDetailsView {
    /// The loading skeleton in the first screen's layout: the poster on the right, then the kind, title, meta, buttons, overview and facts where they land
    private var skeleton: some View {
        ZStack(alignment: .topLeading) {
            SkeletonBlock(cornerRadius: 22)
                .frame(width: 440, height: 660)
                .padding(.top, 130)
                .padding(.trailing, 120)
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 26) {
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 110, height: 28)
                SkeletonBlock(cornerRadius: 14)
                    .frame(width: 760, height: 150)
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 480, height: 29)
                HStack(spacing: 22) {
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 220, height: 76)
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 300, height: 76)
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 76, height: 76)
                }
                .padding(.top, 8)
                SkeletonBlock(cornerRadius: 8)
                    .frame(width: 1000, height: 122)
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 900, height: 74)
                    .padding(.top, 4)
            }
            .padding(.leading, 96)
            .padding(.top, 190)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .loadingSkeleton(isHeld: $isSkeletonHeld)
    }
}
