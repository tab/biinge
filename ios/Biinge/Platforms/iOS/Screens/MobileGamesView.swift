import SwiftUI

struct MobileGamesView: View {
    let store: GameStore
    @State private var selection: Segment = .playing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("gamesSort") private var sort = ListSort.added
    @State private var didDeepLink = false
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(\.presentGame) private var presentGame

    enum Segment: String, CaseIterable {
        case want = "Want"
        case playing = "Playing"
        case played = "Played"
    }

    private var games: [LibraryGame] {
        let games = switch selection {
        case .want: store.wantGames
        case .playing: store.playingGames
        case .played: store.playedGames
        }
        return sort.sorted(games, title: \.title)
    }

    var body: some View {
        NavigationStack {
            // the chosen list cuts in, so old posters never cross the new ones (Reduce Motion crossfades them)
            ZStack {
                VStack(spacing: 0) {
                    content
                }
                .id(selection)
                .transition(reduceMotion ? .opacity : .identity)
            }
            // title and pills move as one block, sliding away as the list scrolls up
            .modifier(CollapsingHeader {
                VStack(spacing: 8) {
                    Text("Games").font(.biingeLargeTitle)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PillFilter(selection: $selection)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            })
            .background(Color.biingeBackground)
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            Text("Date Added").tag(ListSort.added)
                            Text("Title").tag(ListSort.title)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")
                }
            }
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
        if let state = isSkeletonHeld ? .loading : LoadState(hasLoaded: store.hasLoaded, isEmpty: games.isEmpty, loadError: store.loadError) {
            switch state {
            case .loading:
                PosterGridSkeleton(isHeld: $isSkeletonHeld)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t load your games", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await store.load() } }
                        .buttonStyle(.glass)
                        .disabled(store.isLoading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "gamecontroller",
                    description: Text("Games you add will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // a failed refresh keeps the lists an earlier load brought
            if let loadError = store.loadError {
                ErrorBanner(message: "Couldn’t load your games. \(loadError.localizedDescription)") {
                    Task { await store.load() }
                }
                .disabled(store.isLoading)
            }
            PosterGrid(items: games) { game in
                Button {
                    presentGame(game.id)
                } label: {
                    PosterImage(path: game.posterPath, title: game.title, source: .igdb, size: "cover_big_2x")
                        .overlay(alignment: .topTrailing) {
                            if game.pinned { PinBadge() }
                        }
                }
                .buttonStyle(.pressable)
                .detailTransitionSource("game-\(game.id)")
            }
            .refreshable { await store.load() }
        }
    }
}
