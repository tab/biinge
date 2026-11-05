import SwiftUI

struct MobileGameDetailsView: View {
    let gameId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(GameStore.self) private var store
    @Environment(\.presentGame) private var presentGame

    @State private var details: GameDetails?
    @State private var isLoading = true
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    /// Shows the Lists sheet
    @State private var showsLists = false
    /// Bumped when a state change lands, so the haptic fires with the UI rather than on the tap
    @State private var stateChanges = 0
    /// Bumped on the lighter commit: pinning and unpinning
    @State private var marks = 0
    /// The confirmation of the last list change, nil when none shows
    @State private var toast: Toast?

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
        }
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsLists) {
            if let details { listsSheet(details) }
        }
        .task { await load() }
        .sensoryFeedback(.success, trigger: stateChanges)
        .sensoryFeedback(.impact(weight: .light), trigger: marks)
        .toast($toast)
    }

    private func content(_ game: GameDetails) -> some View {
        let state = store.currentState(id: gameId)
        let released = DetailFact.release(game.releaseDate) ?? ""
        let hours = (game.runtime ?? 0) / 60
        let meta = [released, hours > 0 ? "\(hours)h" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let primary = DetailPrimary.game(state: state, isReleased: game.isReleased())
        return VStack(alignment: .leading, spacing: 32) {
            // IGDB's cover size keeps the cover's own 264 × 374 shape, and the slot stays clear until the cover grows in
            Color.clear
                .aspectRatio(264.0 / 374.0, contentMode: .fit)
                .overlay {
                    CachedImage(url: Config.igdbImageURL(imageId: game.posterPath, size: "cover_big_2x"), maxPixel: 600) {
                        Text(game.title)
                            .font(.biingeFootnote)
                            .foregroundStyle(Color.biingeGrayDark)
                            .multilineTextAlignment(.center)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.biingeSecondaryCard)
                    }
                    .environment(\.imageLoadsClear, true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.biingeFill(0.1), lineWidth: 1))
                .detailWatchedBadge(state == .played)
                .frame(width: 216)
                .shadow(color: Color.biingeShadow.opacity(0.55), radius: 35, y: 30)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                // the text arrives 60 ms apart as the sheet grows out of the cover
                Text("Game")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.biingeText.opacity(0.75))
                    .entrance()
                Text(game.title)
                    .font(.biingeLargeTitle)
                    .tracking(-1.2)
                    .entrance()
                HStack(spacing: 12) {
                    if !meta.isEmpty {
                        Text(meta)
                            .foregroundStyle(Color.biingeText.opacity(0.8))
                    }
                    if let rating = game.rating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .labelStyle(RatingLabelStyle())
                    }
                }
                .font(.subheadline)
                .entrance(after: 0.06)
                DetailActionRow(primary: primary, connection: nil) { change(game, to: $0) } secondary: {
                    DetailListButton(pill: DetailListPill(.game, state: state, isPinned: store.isPinned(id: gameId)), fills: primary == nil) {
                        showsLists = true
                    }
                }
                .padding(.top, 4)
                .entrance(after: 0.12)
                if let note = game.releaseNote(state: state) {
                    DetailNote(text: note, systemImage: "calendar")
                        .entrance(after: 0.12)
                }
                if !game.overview.isEmpty {
                    Text(game.overview)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(Color.biingeText.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .entrance(after: 0.18)
                }
            }
            .padding(.horizontal, 16)

            MobileDetailFacts(facts: DetailFact.game(game, state: state))
                .padding(.horizontal, 16)
                .entrance(after: 0.24)
            if !game.genres.isEmpty {
                tagSection("Genres", game.genres)
                    .entrance(after: 0.24)
            }
            if !game.platforms.isEmpty {
                tagSection("Platforms", game.platforms)
                    .entrance(after: 0.24)
            }
            if !game.recommendations.isEmpty {
                DetailSection(title: "Recommendations") { recommendationsRow(game.recommendations) }
                    .entrance(after: 0.24)
            }
        }
        .padding(.top, 72)
        .padding(.bottom, 48)
        // pinned to the scroll view's width, because a page answering a pixel wider pans sideways
        .containerRelativeFrame(.horizontal, alignment: .leading)
        .background(alignment: .top) {
            DetailBackdrop(url: Config.igdbImageURL(imageId: game.posterPath, size: "cover_big"))
        }
    }

    private func tagSection(_ title: String, _ values: [String]) -> some View {
        // titled like Movie and TV sections, such as Cast & Crew
        DetailSection(title: title) {
            TagFlow(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.footnote)
                        .foregroundStyle(Color.biingeText.opacity(0.78))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.biingeFill(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func recommendationsRow(_ items: [Recommendation]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        presentGame(item.id)
                    } label: {
                        PosterImage(path: item.posterPath, title: item.title, source: .igdb, size: "cover_big_2x", cornerRadius: 10)
                            .frame(width: 112)
                            .overlay(alignment: .topLeading) {
                                if store.currentState(id: item.id) != nil { WatchedBadge() }
                            }
                    }
                    .buttonStyle(.pressable)
                    .detailTransitionSource("game-\(item.id)")
                }
            }
            .padding(.horizontal)
        }
    }

    /// The Lists sheet: Want to Play, Playing and Played, Pin in Want and Playing, and Remove
    private func listsSheet(_ game: GameDetails) -> some View {
        DetailListsSheet(
            kind: .game, title: game.title, server: "",
            state: store.currentState(id: gameId), isPinned: store.isPinned(id: gameId)
        ) { target in
            showsLists = false
            change(game, to: target)
        } pin: { pinned in
            showsLists = false
            Task {
                await store.setPinned(id: gameId, pinned: pinned)
                toast = Toast(pinned: pinned)
                marks += 1
            }
        } remove: {
            showsLists = false
            change(game, to: nil)
        }
    }

    /// Moves the game to `target`, or removes it for nil, and confirms the change
    private func change(_ game: GameDetails, to target: WatchState?) {
        Task {
            guard let change = await store.change(
                id: gameId, title: game.title, posterPath: game.posterPath, runtime: game.runtime ?? 0, to: target
            ) else { return }
            toast = change.toast
            stateChanges += 1
            if let failure = await change.outcome.value { toast = failure }
        }
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        // load the library too — opened from Search, the list pill would read an empty store
        async let libraryLoad: Void = store.loadIfNeeded()
        details = try? await apiClient.gameDetails(id: gameId)
        isLoading = false
        if let details {
            store.refreshMetadata(id: gameId, title: details.title, posterPath: details.posterPath)
        }
        await libraryLoad
    }
}

/// Lays chips out in rows that wrap at the available width
private struct TagFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                // offered the row's width, so a chip wider than the row wraps its text inside it
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    /// The subviews' indices in each row, with the row's width and height
    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if let last = rows.last, !last.indices.isEmpty, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
