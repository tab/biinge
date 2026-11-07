import SwiftUI

/// Apple TV game details from biinge: backdrop, title, meta, the next step and list pills with the list menu, the synopsis and facts beside the cover, then the recommendations
struct TVGameDetailsView: View {
    let apiClient: APIClient
    /// The game's IGDB ID
    let id: Int

    @State private var details: GameDetails?
    /// The first load's error message, nil once the details are on screen
    @State private var failure: String?
    /// The confirmation of the last list change or pin, nil when none shows
    @State private var toast: Toast?
    /// The list menu while it shows
    @State private var menu: DetailMenu?
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(GameStore.self) private var store
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
        .background { background(isSkeletonHeld ? nil : Config.igdbImageURL(imageId: details?.posterPath ?? "", size: "1080p")) }
        .defaultFocus($focus, .hero)
        .tvDetailMenu($menu, poster: Config.igdbImageURL(imageId: details?.posterPath ?? "", size: "1080p"), title: details?.title ?? "", toast: $toast) { _ in
            details.map(listRows) ?? []
        }
        .toast($toast)
        .task { await load() }
    }

    /// The game's cover blurred and dimmed behind the page (Home's hero treatment)
    private func background(_ cover: URL?) -> some View {
        ZStack {
            Color.biingeBackground
            if cover != nil {
                TVBackdropArt(url: cover)
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

    private func page(_ game: GameDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(game)
                if !game.recommendations.isEmpty {
                    TVRecommendationsRow(
                        items: game.recommendations, state: store.currentState(id:),
                        poster: { Config.igdbImageURL(imageId: $0.posterPath) },
                        route: { .game(id: $0.id) }
                    )
                    .padding(.bottom, 80)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// The first screen: kind, title, meta, buttons, synopsis, and the facts with genres and platforms beside the cover
    private func header(_ game: GameDetails) -> some View {
        let title = game.title
        let hours = (game.runtime ?? 0) / 60
        let completedHours = (game.runtimeCompleted ?? 0) / 60
        // hours to beat, with the 100% time only when it reads as longer (IGDB's two often round to the same hour)
        let runtime = (game.runtime ?? 0) > 0 ? (completedHours > hours ? "\(hours)h (\(completedHours)h)" : "\(hours)h") : ""
        let meta = [DetailFact.release(game.releaseDate) ?? "", runtime]
        let tags = [DetailFact(label: "Genres", value: game.genres.joined(separator: ", ")), DetailFact(label: "Platforms", value: game.platforms.joined(separator: ", "))].filter { !$0.value.isEmpty }

        return ZStack(alignment: .topLeading) {
            // the slot stays clear until the cover grows in, so the background shows through
            PosterImage(title: title, cornerRadius: 0, poster: Config.igdbImageURL(imageId: game.posterPath, size: "1080p"),
                        frame: CGSize(width: 440, height: 660), titleFont: .system(size: 26), titlePadding: 20)
                .environment(\.imageLoadsClear, true)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.biingeText.opacity(0.1), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if store.isPinned(id: id) { PinBadge() }
                }
                .detailWatchedBadge(store.currentState(id: id) == .played)
                .shadow(color: Color.biingeShadow.opacity(0.6), radius: 45, y: 40)
                .padding(.top, 130)
                .padding(.trailing, 120)
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 26) {
                Text("Game")
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
                    if let rating = game.rating, rating > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.biingePrimary)
                            Text(rating, format: .number.precision(.fractionLength(1)))
                                .fontWeight(.semibold)
                        }
                    }
                }
                .font(.system(size: 29))
                actions(game)
                    .padding(.top, 8)
                if !game.overview.isEmpty {
                    Text(game.overview)
                        .font(.system(size: 30))
                        .lineSpacing(7)
                        .lineLimit(3)
                        .foregroundStyle(Color.biingeText.opacity(0.82))
                        .frame(maxWidth: 1080, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 14) {
                    TVDetailFacts(facts: DetailFact.game(game, state: store.currentState(id: id)))
                    // Genres and Platforms run long, so they keep a row of their own
                    if !tags.isEmpty {
                        TVDetailFacts(facts: tags)
                    }
                }
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

    /// The next step's pill (one list forward) and the list pill, then the note for an unreleased game with its release date or its lack of one
    @ViewBuilder
    private func actions(_ game: GameDetails) -> some View {
        let state = store.currentState(id: id)
        let primary = DetailPrimary.game(state: state, isReleased: game.isReleased())
        let pill = DetailListPill(.game, state: state, isPinned: store.isPinned(id: id))
        HStack(spacing: 22) {
            if let primary, case .move(let target) = primary.action {
                Button {
                    change(game, to: target)
                } label: {
                    Label(primary.title, systemImage: primary.systemImage ?? "bookmark")
                }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .focused($focus, equals: .hero)
                // the add folds the pill away as the list pill takes the list's name
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
            Button { menu = .list } label: {
                ListPillLabel(kind: .game, pill: pill, isUnlisted: state == nil)
            }
            .buttonStyle(PillButtonStyle(isMenu: true, isPinned: pill.isPinned))
            .focused($focus, equals: primary == nil ? .hero : .card(row: "Actions", id: "List"))
        }
        .animation(MotionCurve.exit.animation(MotionDuration.quick), value: primary == nil)
        if let note = game.releaseNote(state: state) {
            Label {
                Text(note)
            } icon: {
                Image(systemName: "calendar").foregroundStyle(Color.biingeTextSecondary)
            }
            .font(.system(size: 26))
            .foregroundStyle(Color.biingeText.opacity(0.6))
        }
    }

    /// The list menu's rows: Want to Play, Playing and Played, then Pin to Up Next and Remove
    private func listRows(_ game: GameDetails) -> [MenuRow] {
        let state = store.currentState(id: id)
        return MenuRow.lists(
            .game, server: "", state: state, isPinned: store.isPinned(id: id),
            move: { change(game, to: $0) },
            pin: { pinned in
                Task { await store.setPinned(id: id, pinned: pinned) }
                toast = Toast(pinned: pinned)
            },
            remove: { change(game, to: nil) }
        )
    }

    /// Moves the game to `target`, or removes it for nil, and confirms the change
    private func change(_ game: GameDetails, to target: WatchState?) {
        Task {
            guard let change = await store.change(
                id: id, title: game.title, posterPath: game.posterPath, runtime: game.runtime ?? 0, to: target
            ) else { return }
            toast = change.toast
            if let failure = await change.outcome.value { toast = failure }
        }
    }

    /// Loads the game from biinge; only a failed first load shows the offline state
    private func load() async {
        do {
            let loaded = try await apiClient.gameDetails(id: id)
            details = loaded
            failure = nil
            store.refreshMetadata(id: id, title: loaded.title, posterPath: loaded.posterPath)
        } catch {
            // leaving the screen cancels the load, which is no failure
            guard !Task.isCancelled else { return }
            if details == nil { failure = error.localizedDescription }
        }
    }
}

extension TVGameDetailsView {
    /// The loading skeleton in the first screen's layout: the cover on the right, then the kind, title, meta, buttons, synopsis and facts where they land
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
                        .frame(width: 300, height: 76)
                    SkeletonBlock(cornerRadius: 38)
                        .frame(width: 260, height: 76)
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
