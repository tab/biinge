import JellyfinAPI
import Observation

/// A series' seasons as the Mac and Apple TV details load them: each season's episodes, the error of a season that failed, and the Jellyfin resume share of the shown season's episodes
@MainActor
@Observable
final class SeasonEpisodes {
    private let apiClient: APIClient
    /// The series' TMDB ID
    private let seriesID: Int

    /// The episodes of each season loaded so far, by season number
    private(set) var episodes: [Int: [EpisodeSummary]] = [:]
    /// The error message of each season whose last load failed, by season number
    private(set) var failures: [Int: String] = [:]
    /// The played share of each episode with a Jellyfin resume position, by Jellyfin item ID (from the last season loadShares asked for)
    private(set) var shares: [String: Double] = [:]

    init(apiClient: APIClient, seriesID: Int) {
        self.apiClient = apiClient
        self.seriesID = seriesID
    }

    /// Loads one season's episodes once; a failure keeps the season's error until a later load of it (Retry, or picking its tab)
    func load(_ number: Int) async {
        guard episodes[number] == nil else { return }
        failures[number] = nil
        do {
            let loaded = try await apiClient.seasonDetails(seriesId: seriesID, season: number).episodes
            episodes[number] = loaded
            // the next visit's skeleton shows as many rows
            SkeletonRows.counts["episodes-\(seriesID)-\(number)"] = loaded.count
        } catch {
            // leaving the screen cancels the load, which is no failure
            guard !Task.isCancelled else { return }
            failures[number] = error.localizedDescription
        }
    }

    /// Loads the resume shares of one season's Jellyfin episodes in one call, by the series' Jellyfin item ID
    func loadShares(season: Int, seriesItemID: String, service: any JellyfinService) async throws {
        shares = ListEntry.resumeShares(try await service.episodes(seriesID: seriesItemID, season: season))
    }

    /// The episode's played share, nil without a Jellyfin item or a resume position
    func share(_ episode: EpisodeSummary) -> Double? {
        episode.jellyfinID.flatMap { shares[$0] }
    }
}
