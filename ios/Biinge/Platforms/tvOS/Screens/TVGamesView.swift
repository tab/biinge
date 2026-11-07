import SwiftUI

/// The Games tab: the biinge Want to Play, Playing and Played lists as cover rows that open each game's details
struct TVGamesView: View {
    @Environment(GameStore.self) private var store
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false

    var body: some View {
        Group {
            if !isSkeletonHeld, store.hasLoaded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 72) {
                        VStack(alignment: .leading, spacing: 32) {
                            HStack(alignment: .firstTextBaseline, spacing: 24) {
                                Text("Games")
                                    .font(.system(size: 76, weight: .bold))
                                    .tracking(76 * -0.03)
                                Text("From your Biinge account")
                                    .font(.system(size: 29))
                                    .foregroundStyle(Color.biingeText.opacity(0.55))
                            }
                            // a failed refresh keeps the lists an earlier load brought
                            if let loadError = store.loadError {
                                HStack(spacing: 32) {
                                    Label("Couldn’t load your games. \(loadError.localizedDescription)", systemImage: "exclamationmark.triangle")
                                        .font(.system(size: 29))
                                        .foregroundStyle(Color(rgb: 0xFF8A8D))
                                    Button { Task { await store.load() } } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(PillButtonStyle())
                                    .disabled(store.isLoading)
                                }
                                .focusSection()
                            }
                        }
                        .padding(.horizontal, 96)
                        GameRow(
                            title: "Want to Play",
                            failed: store.loadError != nil,
                            games: store.wantGames,
                            empty: "Nothing in Want to Play. Add games on iPhone."
                        )
                        GameRow(
                            title: "Playing",
                            failed: store.loadError != nil,
                            games: store.playingGames,
                            empty: "No games in progress. A game moves here when you mark it Playing on iPhone."
                        )
                        GameRow(
                            title: "Played",
                            failed: store.loadError != nil,
                            games: store.playedGames,
                            empty: "Nothing played yet. Games you mark Played on iPhone show up here."
                        )
                    }
                    // the tab bar keeps the header clear
                    .padding(.top, 170)
                    .padding(.bottom, 72)
                }
                .ignoresSafeArea()
            } else if !isSkeletonHeld, let loadError = store.loadError {
                Message(icon: "icloud.slash", title: "Can’t reach Biinge", text: loadError.localizedDescription, action: "Retry") {
                    Task { await store.load() }
                }
            } else {
                ListsSkeleton(isHeld: $isSkeletonHeld)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground.ignoresSafeArea())
        // each visit refreshes the lists, which brings games added on iPhone since the last load
        .task { await store.load() }
    }
}

/// A titled row of game covers that scrolls sideways with focus, or a line of guidance while the list is empty
private struct GameRow: View {
    let title: String
    /// Set while the last load failed, when the error line above stands in for the empty text
    let failed: Bool
    let games: [LibraryGame]
    let empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-0.8)
                if !games.isEmpty {
                    Text("\(games.count)")
                        .font(.system(size: 29))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                }
            }
            .padding(.leading, 96)
            if games.isEmpty {
                if !failed {
                    Text(empty)
                        .font(.system(size: 29))
                        .foregroundStyle(Color.biingeText.opacity(0.6))
                        .padding(.leading, 96)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 48) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                            NavigationLink(value: TVRoute.game(id: game.id)) {
                                PosterImage(title: game.title, cornerRadius: 0, poster: Config.igdbImageURL(imageId: game.posterPath),
                                            frame: CGSize(width: 260, height: 390), titleFont: .system(size: 26), titlePadding: 20)
                            }
                            .buttonStyle(TVCardButtonStyle(width: 260, height: 390, cornerRadius: 16, title: game.title, subtitle: nil))
                            .environment(\.posterFadeIndex, index)
                        }
                    }
                    .padding(.horizontal, 96)
                }
                .scrollClipDisabled()
            }
        }
        .focusSection()
    }
}
