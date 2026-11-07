import SwiftUI

/// The Apple TV top tabs
enum TVTab: Hashable {
    case search, home, movies, series, collections, lists, games, settings
}

/// Apple TV shell: the Jellyfin connect screen until a connection exists or Not Now skips it, then the top tab bar
struct TVRootView: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let connection: JellyfinConnection

    @State private var tab = TVTab.home
    /// Each tab's pushed screens (Home keeps its own)
    @State private var paths: [TVTab: [TVRoute]] = [:]
    @State private var movieStore: MovieStore
    @State private var seriesStore: SeriesStore
    @State private var gameStore: GameStore

    init(authManager: AuthManager, apiClient: APIClient, connection: JellyfinConnection) {
        self.authManager = authManager
        self.apiClient = apiClient
        self.connection = connection
        _movieStore = State(initialValue: MovieStore(apiClient: apiClient))
        _seriesStore = State(initialValue: SeriesStore(apiClient: apiClient))
        _gameStore = State(initialValue: GameStore(apiClient: apiClient))
    }

    var body: some View {
        Group {
            if connection.isConnected || connection.skippedConnect {
                TabView(selection: $tab) {
                    Tab(value: TVTab.search, role: .search) {
                        NavigationStack(path: Binding { paths[.search] ?? [] } set: { paths[.search] = $0 }) {
                            TVSearchView(apiClient: apiClient)
                                .tvRouteDestinations(connection: connection, apiClient: apiClient)
                        }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    Tab(value: TVTab.home) {
                        if connection.isConnected {
                            TVHomeView(connection: connection, apiClient: apiClient, tab: $tab)
                        } else {
                            connectPrompt
                        }
                    } label: {
                        Text("Home")
                    }
                    Tab(value: TVTab.movies) {
                        if connection.isConnected {
                            NavigationStack(path: Binding { paths[.movies] ?? [] } set: { paths[.movies] = $0 }) {
                                TVLibraryView(connection: connection, isMovies: true)
                                    .tvRouteDestinations(connection: connection, apiClient: apiClient)
                            }
                        } else {
                            connectPrompt
                        }
                    } label: {
                        Text("Movies")
                    }
                    Tab(value: TVTab.series) {
                        if connection.isConnected {
                            NavigationStack(path: Binding { paths[.series] ?? [] } set: { paths[.series] = $0 }) {
                                TVLibraryView(connection: connection, isMovies: false)
                                    .tvRouteDestinations(connection: connection, apiClient: apiClient)
                            }
                        } else {
                            connectPrompt
                        }
                    } label: {
                        Text("TV Shows")
                    }
                    Tab(value: TVTab.collections) {
                        if connection.isConnected {
                            NavigationStack(path: Binding { paths[.collections] ?? [] } set: { paths[.collections] = $0 }) {
                                TVCollectionsView(connection: connection)
                                    .tvRouteDestinations(connection: connection, apiClient: apiClient)
                            }
                        } else {
                            connectPrompt
                        }
                    } label: {
                        Text("Collections")
                    }
                    Tab(value: TVTab.lists) {
                        // the lists come from biinge, so they show with or without Jellyfin
                        NavigationStack(path: Binding { paths[.lists] ?? [] } set: { paths[.lists] = $0 }) {
                            TVListsView(connection: connection)
                                .tvRouteDestinations(connection: connection, apiClient: apiClient)
                        }
                    } label: {
                        Text("My Lists")
                    }
                    Tab(value: TVTab.games) {
                        // the games come from biinge, so they show with or without Jellyfin
                        NavigationStack(path: Binding { paths[.games] ?? [] } set: { paths[.games] = $0 }) {
                            TVGamesView()
                                .tvRouteDestinations(connection: connection, apiClient: apiClient)
                        }
                    } label: {
                        Text("Games")
                    }
                    Tab(value: TVTab.settings) {
                        NavigationStack {
                            TVSettingsView(authManager: authManager, apiClient: apiClient, connection: connection)
                        }
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                }
                // a card that resolves its details first pushes onto the selected tab's stack
                .environment(\.tvOpen, TVOpenAction { route in paths[tab, default: []].append(route) })
            } else {
                TVConnectView(connection: connection, apiClient: apiClient)
            }
        }
        // a new connection opens on Home
        .onChange(of: connection.isConnected) { _, isConnected in
            guard isConnected else { return }
            tab = .home
            paths = [:]
        }
        // a play Jellyfin reports as played marks the movie or episode watched in biinge too
        .onChange(of: connection.playbackEnded) {
            guard let item = connection.finishedPlay, let service = connection.service else { return }
            Task {
                // shortcut: a failed write goes unreported, as the player has closed; surface it if marks go missing in use
                guard let title = try? await DetailsTitle.resolve(item, service: service),
                      let mark = PlayedMark(item, title: title, isWatchedMovie: { movieStore.currentState(id: $0) == .watched }) else { return }
                try? await mark.write(apiClient: apiClient, movies: movieStore, series: seriesStore)
            }
        }
        // a Play whose lookup or item fetch failed says why and offers it again
        .playFailureAlert(connection: connection)
        // dismissing the player, by Menu or otherwise, stops playback
        .fullScreenCover(isPresented: Binding(
            get: { connection.playback != nil },
            set: { if !$0 { Task { await connection.stopPlayback() } } }
        )) {
            if let session = connection.playback {
                TVPlayerView(connection: connection, apiClient: apiClient, session: session)
                    // the shell's alert can't show over the cover, so the player gives the next episode's fetch its own
                    .playFailureAlert(connection: connection)
            }
        }
        // the details read the user's library from the stores, as on iPhone and Mac, and so can the player above the tabs
        .environment(movieStore)
        .environment(seriesStore)
        .environment(gameStore)
        .task {
            async let movies: Void = movieStore.loadIfNeeded()
            async let series: Void = seriesStore.loadIfNeeded()
            async let games: Void = gameStore.loadIfNeeded()
            _ = await (movies, series, games)
        }
    }

    /// The library tabs read Jellyfin, so after Not Now they ask to connect (clearing Not Now brings back the connect screen)
    private var connectPrompt: some View {
        Message(
            icon: "link",
            title: "Connect Jellyfin to browse",
            text: "Your lists, search and title details come from Biinge and still work. Connect your Jellyfin account to browse and play what the server holds.",
            action: "Connect Jellyfin",
            actionIcon: "link",
            secondAction: ("Open My Lists", "bookmark", { tab = .lists })
        ) {
            connection.skippedConnect = false
        }
    }
}
