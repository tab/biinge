import SwiftUI

/// A biinge Games list (Want to Play, Playing or Played): the title and count over a cover grid whose covers open their details
struct DesktopGamesView: View {
    /// .wantToPlay, .playing or .played
    let section: DesktopSection

    @Environment(GameStore.self) private var store
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false

    var body: some View {
        let games = switch section {
        case .wantToPlay: store.wantGames
        case .playing: store.playingGames
        default: store.playedGames
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(section.title)
                        .font(.system(size: 44, weight: .bold))
                        .tracking(-1.3)
                    if !games.isEmpty {
                        Text(games.count == 1 ? "1 game" : "\(games.count) games")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                // a failed refresh keeps the lists an earlier load brought
                if let loadError = store.loadError {
                    HStack(spacing: 14) {
                        Label("Couldn’t load your games. \(loadError.localizedDescription)", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(rgb: 0xFF8A8D))
                        Button("Retry") { Task { await store.load() } }
                            .disabled(store.isLoading)
                    }
                }
                if !isSkeletonHeld, !games.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 22)], alignment: .leading, spacing: 30) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                            NavigationLink(value: DesktopRoute.game(id: game.id)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Color.clear
                                        .aspectRatio(2 / 3, contentMode: .fit)
                                        .overlay {
                                            GeometryReader { proxy in
                                                PosterImage(title: game.title, cornerRadius: 0, poster: Config.igdbImageURL(imageId: game.posterPath),
                                                            frame: proxy.size, titleFont: .system(size: 14), titlePadding: 12)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.biingeText.opacity(0.07), lineWidth: 1))
                                        .posterHover(cornerRadius: 10)
                                        .environment(\.posterFadeIndex, index)
                                    Text(game.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .lineLimit(1)
                                }
                                // the whole cover and caption take the click
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(game.title)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else if !isSkeletonHeld, store.loadError != nil {
                    // the error line above stands in for the empty state
                    EmptyView()
                } else if isSkeletonHeld || !store.hasLoaded {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 22)], alignment: .leading, spacing: 30) {
                        ForEach(0..<12, id: \.self) { _ in
                            PosterSkeleton(cornerRadius: 10, caption: 14)
                        }
                    }
                    .loadingSkeleton(isHeld: $isSkeletonHeld)
                } else {
                    ContentUnavailableView {
                        switch section {
                        case .wantToPlay: Label("Nothing in Want to Play", systemImage: "bookmark")
                        case .playing: Label("No games in progress", systemImage: "gamecontroller")
                        default: Label("Nothing played yet", systemImage: "checkmark.circle")
                        }
                    } description: {
                        switch section {
                        case .wantToPlay: Text("Add games on iPhone. The list is the same one you see there and on Apple TV.")
                        case .playing: Text("A game moves here when you mark it Playing on iPhone.")
                        default: Text("Mark a game Played on iPhone and it shows up here.")
                        }
                    }
                    .padding(.vertical, 60)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .navigationTitle(section.title)
        // each visit refreshes the lists, which brings games added on iPhone since the last load
        .task(id: section) { await store.load() }
    }
}
