import Observation

/// Holds the user's movie library (want / watched), mirroring the RN MovieContext.
@MainActor
@Observable
final class MovieStore {
    private(set) var wantMovies: [LibraryMovie] = []
    private(set) var watchedMovies: [LibraryMovie] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        isLoading = true
        async let want = fetch(type: "want")
        async let watched = fetch(type: "watched")
        let (wantResult, watchedResult) = await (want, watched)
        if let wantResult { wantMovies = wantResult }
        if let watchedResult { watchedMovies = watchedResult }
        isLoading = false
        hasLoaded = true
    }

    private func fetch(type: String) async -> [LibraryMovie]? {
        try? await apiClient.movies(type: type).data
    }
}
