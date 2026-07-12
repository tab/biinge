import SwiftUI

/// The authenticated shell: a four-tab layout matching the RN app.
struct RootView: View {
    let authManager: AuthManager
    let apiClient: APIClient

    @State private var movieStore: MovieStore
    @State private var tvStore: TvStore
    @State private var selection: Int

    init(authManager: AuthManager, apiClient: APIClient) {
        self.authManager = authManager
        self.apiClient = apiClient
        _movieStore = State(initialValue: MovieStore(apiClient: apiClient))
        _tvStore = State(initialValue: TvStore(apiClient: apiClient))

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
                MoviesView(store: movieStore)
            }
            Tab("TV", systemImage: "tv", value: 1) {
                TvView(store: tvStore)
            }
            Tab("Search", systemImage: "magnifyingglass", value: 2) {
                SearchView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: 3) {
                ProfileView(authManager: authManager)
            }
        }
        .tint(Color.biingePrimary)
        .environment(movieStore)
        .environment(tvStore)
        .environment(\.apiClient, apiClient)
    }
}
