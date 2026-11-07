import JellyfinAPI

/// What a Play outside details does with a Jellyfin item, by the biinge details' one-match rule
enum PlayResolution: Equatable {
    /// Plays this fresh Jellyfin item, the one the biinge details name
    case play(BaseItemDto)
    /// Opens these details instead (a series or a season, or a title whose biinge details name no single Jellyfin item)
    case details(DetailsTitle)
    /// Does nothing (no TMDB ID to look the item up by)
    case nothing

    /// Looks the item up in biinge (a movie by its TMDB ID, an episode by its series' TMDB ID and its numbers) and fetches the Jellyfin item the details name
    @MainActor
    static func resolve(_ item: BaseItemDto, service: any JellyfinService, apiClient: APIClient) async throws -> PlayResolution {
        let title: DetailsTitle
        let jellyfinID: String?
        switch item.type {
        case .movie:
            guard case .movie(let id) = DetailsTitle(item) else { return .nothing }
            title = .movie(id)
            jellyfinID = try await apiClient.movieDetails(id: id).jellyfinID
        case .episode:
            guard case .series(let id) = try await DetailsTitle.resolve(item, service: service) else { return .nothing }
            title = .series(id)
            // without its numbers the episode has no biinge details, so its series picks the episode
            guard let season = item.parentIndexNumber, let episode = item.indexNumber else { return .details(title) }
            jellyfinID = try await apiClient.episodeDetails(seriesId: id, season: season, episode: episode).jellyfinID
        default:
            // a series or a season never plays directly, as its details pick the episode
            return try await DetailsTitle.resolve(item, service: service).map(PlayResolution.details) ?? .nothing
        }
        guard let jellyfinID else { return .details(title) }
        // a fresh item, so the play resumes from the position Jellyfin holds now
        return .play(try await service.item(id: jellyfinID))
    }

    /// Resolves the item, then plays the one biinge names (from zero with fromStart) or opens the details it resolves to
    @MainActor
    static func play(_ item: BaseItemDto, fromStart: Bool, connection: JellyfinConnection, apiClient: APIClient, open: (DetailsTitle) -> Void) async throws {
        guard let service = connection.service else { return }
        switch try await resolve(item, service: service, apiClient: apiClient) {
        case .play(let resolved): await connection.play(resolved, fromStart: fromStart)
        case .details(let title): open(title)
        case .nothing: break
        }
    }
}
