import SwiftUI

/// Mac game details from biinge: the blurred backdrop, cover, title, meta, the white pill, list button and More, the synopsis, genres and platforms, then the facts and the recommendations
struct DesktopGameDetailsView: View {
    let apiClient: APIClient
    /// The game's IGDB ID
    let id: Int

    @State private var details: GameDetails?
    /// The first load's error message, nil once the details are on screen
    @State private var failure: String?
    /// The confirmation of the last list or pin change, nil when none shows
    @State private var toast: Toast?
    /// Set while the list menu shows under the list button
    @State private var isListMenuOpen = false
    /// Set while the page skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(GameStore.self) private var store
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
    }

    private func page(_ game: GameDetails) -> some View {
        let title = game.title
        let hours = (game.runtime ?? 0) / 60
        let completedHours = (game.runtimeCompleted ?? 0) / 60
        // hours to beat, with the 100% time only when it reads as longer (IGDB's two often round to the same hour)
        let runtime = (game.runtime ?? 0) > 0 ? (completedHours > hours ? "\(hours)h (\(completedHours)h)" : "\(hours)h") : ""
        let meta = [DetailFact.release(game.releaseDate) ?? "", runtime]
        let facts = [("Genres", game.genres.joined(separator: ", ")), ("Platforms", game.platforms.joined(separator: ", "))].filter { !$0.1.isEmpty }
        let cover = Config.igdbImageURL(imageId: game.posterPath, size: "1080p")
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 48) {
                    // the slot stays clear until the cover grows in, so the backdrop shows through
                    PosterImage(title: title, cornerRadius: 0, poster: cover, frame: CGSize(width: 290, height: 435), titleFont: .system(size: 14), titlePadding: 12)
                        .environment(\.imageLoadsClear, true)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.biingeText.opacity(0.1), lineWidth: 1))
                        .detailWatchedBadge(store.currentState(id: id) == .played)
                        .shadow(color: Color.biingeShadow.opacity(0.55), radius: 40, y: 34)
                    // the text arrives 60 ms apart
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Game")
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
                            if let rating = game.rating, rating > 0 {
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
                        actions(game)
                            .entrance(after: 0.12)
                        if !game.overview.isEmpty {
                            Text(game.overview)
                                .font(.system(size: 18))
                                .lineSpacing(5)
                                .opacity(0.82)
                                .frame(maxWidth: 680, alignment: .leading)
                                .entrance(after: 0.18)
                        }
                        if !facts.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(facts, id: \.0) { label, value in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(label)
                                            .opacity(0.55)
                                        Text(value)
                                            .opacity(0.8)
                                    }
                                }
                            }
                            .font(.system(size: 15))
                            .frame(maxWidth: 680, alignment: .leading)
                            .entrance(after: 0.18)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 100)
                .padding(.horizontal, 40)
                .padding(.bottom, 80)
                .background(alignment: .top) {
                    // the art blurred and dimmed behind the header, fading into the page at the bottom
                    DetailBackdrop(url: cover, height: nil, blur: 80, bleed: 120, fadeStart: 0.3, topOverlap: 0)
                }
                DesktopDetailFacts(facts: DetailFact.game(game, state: store.currentState(id: id)))
                    .padding(.horizontal, 40)
                    .padding(.bottom, game.recommendations.isEmpty ? 80 : 44)
                    .entrance(after: 0.24)
                if !game.recommendations.isEmpty {
                    RecommendationsRow(
                        items: game.recommendations, state: store.currentState(id:),
                        poster: { Config.igdbImageURL(imageId: $0.posterPath) },
                        route: { .game(id: $0.id) }
                    )
                    .padding(.bottom, 80)
                    .entrance(after: 0.24)
                }
            }
        }
    }

    /// The white pill one list forward from DetailPrimary, the list button and More, then the note for an unreleased game with its release date or its lack of one
    @ViewBuilder
    private func actions(_ game: GameDetails) -> some View {
        let state = store.currentState(id: id)
        let primary = DetailPrimary.game(state: state, isReleased: game.isReleased())
        HStack(spacing: 12) {
            if let primary {
                // a game's pill only ever moves it between lists
                PrimaryPill(primary: primary, server: "") {
                    if case .move(let target) = primary.action { change(game, to: target) }
                }
                // the add folds away on Exit over Quick as the list button takes its place (Reduce Motion fades it)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            }
            ListButton(pill: DetailListPill(.game, state: state, isPinned: store.isPinned(id: id)), isOpen: $isListMenuOpen)
            MoreMenu(kind: .game, id: id, apiClient: apiClient, startOver: nil, markSeason: nil)
        }
        .animation(MotionCurve.exit.animation(MotionDuration.quick), value: primary == nil)
        if let note = game.releaseNote(state: state) {
            DesktopDetailNote(systemImage: "calendar", text: note)
        }
    }

    /// The list menu under the list button, which closes on a pick and confirms it with a toast
    private func listMenu(_ game: GameDetails) -> ListMenu {
        let state = store.currentState(id: id)
        let close = { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { isListMenuOpen = false } }
        return ListMenu(kind: .game, state: state, isPinned: store.isPinned(id: id), server: "") { target in
            close()
            change(game, to: target)
        } togglePin: {
            close()
            let pinned = !store.isPinned(id: id)
            Task { await store.setPinned(id: id, pinned: pinned) }
            toast = Toast(pinned: pinned)
        } remove: {
            close()
            change(game, to: nil)
        }
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
