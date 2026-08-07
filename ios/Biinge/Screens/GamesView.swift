import SwiftUI

struct GamesView: View {
    let store: GameStore
    @State private var selection: Segment = .playing
    @State private var didDeepLink = false
    @Environment(\.presentGame) private var presentGame

    enum Segment: String, CaseIterable {
        case want = "Want"
        case playing = "Playing"
        case played = "Played"
    }

    private var games: [LibraryGame] {
        switch selection {
        case .want: return store.wantGames
        case .playing: return store.playingGames
        case .played: return store.playedGames
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selection) {
                    ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                content
            }
            .navigationTitle("Games")
            .upNextToolbar()
        }
        .task {
            await store.loadIfNeeded()
            #if DEBUG
            if !didDeepLink, let raw = ProcessInfo.processInfo.environment["DEBUG_GAME_ID"], let id = Int(raw) {
                didDeepLink = true
                presentGame(id)
            }
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && !store.hasLoaded {
            ProgressView().tint(Color.biingeLoader)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if games.isEmpty {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "gamecontroller",
                description: Text("Games you add will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PosterGrid(items: games) { game in
                Button {
                    presentGame(game.id)
                } label: {
                    PosterImage(path: game.posterPath, title: game.title, source: .igdb, size: "cover_big_2x")
                        .overlay(alignment: .topTrailing) {
                            if game.pinned { PinBadge() }
                        }
                }
                .buttonStyle(.plain)
            }
            .refreshable { await store.load() }
        }
    }
}
