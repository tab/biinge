import Observation

/// Holds the user's ready-to-watch queue, kept outside the sheet so reopening it shows the last queue while the refresh runs
@MainActor
@Observable
final class UpNextStore {
    private(set) var upNext: UpNext?
    private(set) var isLoading = false
    private(set) var failed = false

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        do {
            upNext = try await apiClient.upNext()
            failed = false
        } catch {
            failed = true
        }
        isLoading = false
    }
}
