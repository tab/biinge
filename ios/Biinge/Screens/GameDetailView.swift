import SwiftUI

struct GameDetailView: View {
    let gameId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(GameStore.self) private var store
    @Environment(\.presentGame) private var presentGame

    @State private var details: GameDetails?
    @State private var isLoading = true
    @State private var showMenu = false
    /// Bumped when a state change lands, so the haptic fires with the UI rather than on the tap
    @State private var stateChanges = 0
    /// Bumped on the lighter commit: pinning and unpinning
    @State private var marks = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
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

            CloseButton()
        }
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sensoryFeedback(.success, trigger: stateChanges)
        .sensoryFeedback(.impact(weight: .light), trigger: marks)
        .overlay {
            if showMenu, let details {
                GameActionMenu(
                    posterPath: details.posterPath,
                    state: store.currentState(id: gameId),
                    pinned: store.isPinned(id: gameId),
                    onAction: { action in Task { await handleMenu(action, details) } },
                    onCancel: { withAnimation(.spring(duration: 0.3, bounce: 0)) { showMenu = false } }
                )
            }
        }
    }

    private func content(_ game: GameDetails) -> some View {
        VStack(spacing: 0) {
            PosterImage(path: game.posterPath, title: game.title, source: .igdb, size: "1080p", cornerRadius: 12)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.7 }
                .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                .padding(.top, 64)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text(game.title).font(.biingeTitle1).foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    if let rating = game.rating, rating > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").font(.biingeTitle3).foregroundStyle(Color.biingePrimary)
                            Text(String(format: "%.1f", rating)).font(.biingeTitle2).fontWeight(.heavy).foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 15)

                HStack {
                    Text(formatDate(game.releaseDate)).foregroundStyle(Color.biingeGraniteGray)
                    Spacer()
                    Text(formatRuntime(game.runtime, completed: game.runtimeCompleted)).foregroundStyle(Color.biingeSpanishGray)
                    Spacer()
                    statusPill(game.status)
                }
                .font(.biingeCallout)
                .padding(.horizontal, 15)

                GameActionsView(gameId: gameId, details: game, showMenu: $showMenu)
                    .padding(.horizontal, 15)

                if !game.overview.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Synopsis").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray)
                        Text(game.overview).font(.biingeBody).foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 15)
                }

                if !game.genres.isEmpty {
                    tagSection("Genres", game.genres)
                }
                if !game.platforms.isEmpty {
                    tagSection("Platforms", game.platforms)
                }
                if !game.recommendations.isEmpty {
                    recommendationsSection(game.recommendations)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCardBackground()
        }
    }

    // A plain HStack reports the full row width as its ideal, which the outer ScrollView adopts as its
    // content width and lets the whole page pan sideways; LazyHStack sizes to what is on screen
    private func tagSection(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray).padding(.horizontal, 15)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(.biingeFootnote)
                            .foregroundStyle(Color.biingeTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.biingeSecondaryCard, in: Capsule())
                    }
                }
                .padding(.horizontal, 15)
            }
        }
    }

    private func recommendationsSection(_ items: [Recommendation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommendations").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray).padding(.horizontal, 15)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            presentGame(item.id)
                        } label: {
                            PosterImage(path: item.posterPath, title: item.title, source: .igdb, size: "cover_big_2x")
                                .frame(width: 120)
                                .overlay(alignment: .topLeading) {
                                    if isTracked(item) { WatchedBadge() }
                                }
                        }
                        .buttonStyle(.pressable)
                        .detailTransitionSource("game-\(item.id)")
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

    @ViewBuilder
    private func statusPill(_ status: String?) -> some View {
        if let status, !status.isEmpty {
            Text(status)
                .font(.system(.caption, weight: .bold))
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

    /// Hours to beat, with the 100% time in parentheses only when it reads as longer. IGDB's completely
    /// figure is sometimes level with normally, and the two round to the same hour more often than not
    private func formatRuntime(_ minutes: Int?, completed: Int?) -> String {
        guard let minutes, minutes > 0 else { return "" }
        let hours = minutes / 60
        let completedHours = (completed ?? 0) / 60
        guard completedHours > hours else { return "\(hours)h" }
        return "\(hours)h (\(completedHours)h)"
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        // load the library too — opened from Search, the state pill would read an empty store
        async let libraryLoad: Void = store.loadIfNeeded()
        details = try? await apiClient.gameDetails(id: gameId)
        isLoading = false
        if let details {
            store.refreshMetadata(id: gameId, title: details.title, posterPath: details.posterPath)
        }
        await libraryLoad
    }

    private func handleMenu(_ action: GameActionMenu.MenuAction, _ game: GameDetails) async {
        // the menu stays open on actions; only Cancel dismisses it
        switch action {
        case .toggle(let target):
            await store.toggle(id: gameId, title: game.title, posterPath: game.posterPath, runtime: game.runtime ?? 0, target: target)
            stateChanges += 1
        case .pin:
            await store.setPinned(id: gameId, pinned: true)
            marks += 1
        case .unpin:
            await store.setPinned(id: gameId, pinned: false)
            marks += 1
        }
    }
}

/// The action row on a game: three white pills, or a single accent pill when tracked
struct GameActionsView: View {
    let gameId: Int
    let details: GameDetails
    @Binding var showMenu: Bool
    @Environment(GameStore.self) private var store
    /// Bumped when a state change lands, so the haptic fires with the UI rather than on the tap
    @State private var stateChanges = 0

    var body: some View {
        let state = store.currentState(id: gameId)
        Group {
            if let state {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0)) { showMenu = true }
                } label: {
                    Text(GameActionMenu.label(for: state))
                        .font(.biingeCallout).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Color.biingeAccent, in: Capsule())
                }
                .buttonStyle(.pressable)
            } else {
                // Played is reached through the menu once tracked, so an untracked game offers the two
                // states you actually start from
                HStack(spacing: 10) {
                    actionPill("Want", target: .want)
                    actionPill("Playing", target: .playing)
                }
            }
        }
        .sensoryFeedback(.success, trigger: stateChanges)
    }

    private func actionPill(_ title: String, target: WatchState) -> some View {
        Button {
            Task {
                await store.toggle(
                    id: gameId, title: details.title, posterPath: details.posterPath,
                    runtime: details.runtime ?? 0, target: target
                )
                stateChanges += 1
            }
        } label: {
            Text(title).font(.biingeCallout).fontWeight(.semibold)
                .foregroundStyle(Color.biingeBackground)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Color.biingeText, in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// The full-screen action menu shown when tapping a tracked game's state pill
struct GameActionMenu: View {
    let posterPath: String
    let state: WatchState?
    let pinned: Bool
    let onAction: (MenuAction) -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    enum MenuAction {
        case toggle(WatchState)
        case pin
        case unpin
    }

    /// Segment name for a tracked state, shown on the pill and in the menu options
    static func label(for state: WatchState) -> String {
        switch state {
        case .playing: return "Playing"
        case .played: return "Played"
        default: return "Want"
        }
    }

    var body: some View {
        ZStack {
            // one solid scrim where the user asked for less transparency, the frosted pair otherwise
            if reduceTransparency {
                Color.black.opacity(0.82).ignoresSafeArea()
            } else {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                Color.black.opacity(0.4).ignoresSafeArea()
            }

            Button(action: onCancel) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Button(action: onCancel) {
                    PosterImage(path: posterPath, title: "", source: .igdb, size: "cover_big_2x", cornerRadius: 12)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.55 }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close")

                VStack(spacing: 2) {
                    ForEach(options, id: \.title) { option in
                        Button(action: option.action) {
                            Text(option.title)
                                .font(.biingeBody).fontWeight(.semibold)
                                .foregroundStyle(Color.biingeText.opacity(0.7))
                                .padding(10)
                        }
                        .buttonStyle(.pressable)
                    }
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.biingeBody).fontWeight(.semibold)
                            .foregroundStyle(Color.biingeText.opacity(0.7))
                            .padding(10)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 15)
            // the menu materialises out of the scrim instead of fading flat onto it
            .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
        }
        .transition(.opacity)
    }

    /// Remove from the current state, move to either of the other two, then pin
    private var options: [(title: String, action: () -> Void)] {
        guard let state else {
            return [
                ("Want", { onAction(.toggle(.want)) }),
                ("Playing", { onAction(.toggle(.playing)) }),
                ("Played", { onAction(.toggle(.played)) }),
            ]
        }
        let others: [WatchState] = [.want, .playing, .played].filter { $0 != state }
        return [("Remove from \(Self.label(for: state))", { onAction(.toggle(state)) })]
            + others.map { target in ("Move to \(Self.label(for: target))", { onAction(.toggle(target)) }) }
            + [(pinned ? "Unpin" : "Pin", { onAction(pinned ? .unpin : .pin) })]
    }
}
