import Observation

/// Holds the user's TV library (want / watching / watched), mirroring the RN TvContext.
@MainActor
@Observable
final class TvStore {
    private(set) var wantShows: [LibrarySeries] = []
    private(set) var watchingShows: [LibrarySeries] = []
    private(set) var watchedShows: [LibrarySeries] = []
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
        async let watching = fetch(type: "watching")
        async let watched = fetch(type: "watched")
        let (wantResult, watchingResult, watchedResult) = await (want, watching, watched)
        if let wantResult { wantShows = wantResult }
        if let watchingResult { watchingShows = watchingResult }
        if let watchedResult { watchedShows = watchedResult }
        isLoading = false
        hasLoaded = true
    }

    private func fetch(type: String) async -> [LibrarySeries]? {
        try? await apiClient.series(type: type).data
    }
}
