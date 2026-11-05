import SwiftUI

/// The authenticated shell: Connect Jellyfin after a fresh login, then a four-tab layout matching the RN app
struct MobileRootView: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let connection: JellyfinConnection

    @State private var movieStore: MovieStore
    @State private var seriesStore: SeriesStore
    @State private var gameStore: GameStore
    @State private var upNextStore: UpNextStore
    @State private var selection: Int
    /// Set by the Library's Connect in Profile, so Profile opens its Jellyfin sheet
    @State private var opensJellyfin = false

    init(authManager: AuthManager, apiClient: APIClient, connection: JellyfinConnection) {
        self.authManager = authManager
        self.apiClient = apiClient
        self.connection = connection
        _movieStore = State(initialValue: MovieStore(apiClient: apiClient))
        _seriesStore = State(initialValue: SeriesStore(apiClient: apiClient))
        _gameStore = State(initialValue: GameStore(apiClient: apiClient))
        _upNextStore = State(initialValue: UpNextStore(apiClient: apiClient, connection: connection))

        var initialTab = 0
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["INITIAL_TAB"], let index = Int(raw) {
            initialTab = index
        }
        #endif
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            if authManager.connectsJellyfinFirst {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Connect Jellyfin")
                            .font(.biingeLargeTitle)
                        MobileConnectView(connection: connection, apiClient: apiClient) {
                            connection.skippedConnect = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 40)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Color.biingeBackground.ignoresSafeArea())
                .foregroundStyle(Color.biingeText)
            } else {
                tabs
            }
        }
        // the connect step ends with a connection or Not Now, so a later Disconnect or Reconnect stays in Profile's sheet
        .onChange(of: connection.isConnected || connection.skippedConnect, initial: true) { _, ended in
            if ended { authManager.connectsJellyfinFirst = false }
        }
        // the API matches Jellyfin items for the connected account, so a new connection reloads the lists with them
        .onChange(of: connection.userID) {
            Task {
                async let movies: Void = movieStore.load()
                async let series: Void = seriesStore.load()
                _ = await (movies, series)
            }
        }
        // a play Jellyfin reports as played marks the movie or episode watched in biinge too, and the stores update the lists
        .onChange(of: connection.playbackEnded) {
            guard let item = connection.finishedPlay, let service = connection.service else { return }
            Task {
                // shortcut: a failed write goes unreported, as the player has closed; surface it if marks go missing in use
                guard let title = try? await DetailsTitle.resolve(item, service: service),
                      let mark = PlayedMark(item, title: title, isWatchedMovie: { movieStore.currentState(id: $0) == .watched }) else { return }
                try? await mark.write(apiClient: apiClient, movies: movieStore, series: seriesStore)
            }
        }
        .presentsPlayer(connection: connection, apiClient: apiClient)
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Movies", systemImage: "film", value: 0) {
                MoviesView(store: movieStore, connection: connection, connectInProfile: connectInProfile).presentsDetails()
            }
            Tab("TV", systemImage: "tv", value: 1) {
                SeriesView(store: seriesStore, connection: connection, connectInProfile: connectInProfile) { selection = 4 }
                    .presentsDetails()
            }
            // Games took the slot Up Next held; the queue spans movies and shows, so it hangs off every
            // library screen's toolbar instead of one tab
            Tab("Games", systemImage: "gamecontroller", value: 2) {
                MobileGamesView(store: gameStore).presentsDetails()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: 3) {
                ProfileView(authManager: authManager, apiClient: apiClient, connection: connection, opensJellyfin: $opensJellyfin)
            }
            // the search role, so the tab bar itself becomes the field
            Tab("Search", systemImage: "magnifyingglass", value: 4, role: .search) {
                MobileSearchView().presentsDetails()
            }
        }
        .tint(Color.biingeText)
        .environment(movieStore)
        .environment(seriesStore)
        .environment(gameStore)
        .environment(upNextStore)
        // poster checks read the stores on every tab, so all three load once the tabs show
        .task {
            async let movies: Void = movieStore.loadIfNeeded()
            async let series: Void = seriesStore.loadIfNeeded()
            async let games: Void = gameStore.loadIfNeeded()
            _ = await (movies, series, games)
        }
        .environment(connection)
        .environment(\.apiClient, apiClient)
        .playFailureAlert(connection: connection)
    }

    /// Switches to Profile with its Jellyfin sheet open
    private func connectInProfile() {
        selection = 3
        opensJellyfin = true
    }
}
