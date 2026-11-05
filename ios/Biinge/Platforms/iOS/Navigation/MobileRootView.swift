import SwiftUI

/// The authenticated shell: a four-tab layout matching the RN app
struct RootView: View {
    let authManager: AuthManager
    let apiClient: APIClient

    @State private var movieStore: MovieStore
    @State private var tvStore: TvStore
    @State private var gameStore: GameStore
    @State private var upNextStore: UpNextStore
    @State private var selection: Int

    init(authManager: AuthManager, apiClient: APIClient) {
        self.authManager = authManager
        self.apiClient = apiClient
        _movieStore = State(initialValue: MovieStore(apiClient: apiClient))
        _tvStore = State(initialValue: TvStore(apiClient: apiClient))
        _gameStore = State(initialValue: GameStore(apiClient: apiClient))
        _upNextStore = State(initialValue: UpNextStore(apiClient: apiClient))

        var initialTab = 0
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["INITIAL_TAB"], let index = Int(raw) {
            initialTab = index
        }
        #endif
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Movies", systemImage: "film", value: 0) {
                MoviesView(store: movieStore).presentsDetails()
            }
            Tab("TV", systemImage: "tv", value: 1) {
                TvView(store: tvStore).presentsDetails()
            }
            // Games took the slot Up Next held; the queue spans movies and shows, so it hangs off every
            // library screen's toolbar instead of one tab
            Tab("Games", systemImage: "gamecontroller", value: 2) {
                GamesView(store: gameStore).presentsDetails()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: 3) {
                ProfileView(authManager: authManager)
            }
            // the search role, so the tab bar itself becomes the field
            Tab("Search", systemImage: "magnifyingglass", value: 4, role: .search) {
                SearchView().presentsDetails()
            }
        }
        .tint(Color.biingeText)
        .environment(movieStore)
        .environment(tvStore)
        .environment(gameStore)
        .environment(upNextStore)
        .environment(\.apiClient, apiClient)
    }
}
