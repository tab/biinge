import JellyfinAPI
import SwiftUI

/// A screen pushed onto an Apple TV tab's navigation stack
enum TVRoute: Hashable {
    /// A movie's or a series' biinge details, showing the Jellyfin poster of the tile they opened from in place of the TMDB one (nil for the TMDB poster)
    case title(DetailsTitle, poster: URL? = nil)
    /// An episode's biinge details, by the series' TMDB ID and the season and episode numbers
    case episode(series: Int, season: Int, episode: Int)
    case collection(BaseItemDto)
    /// A person's biinge page, by TMDB ID
    case person(id: Int)
    /// A game's biinge details, by IGDB ID
    case game(id: Int)
}

/// Pushes a screen onto the current tab's navigation stack (for a card that resolves its details before it opens them)
struct TVOpenAction: Equatable {
    let perform: @MainActor (TVRoute) -> Void

    @MainActor func callAsFunction(_ route: TVRoute) {
        perform(route)
    }

    // the writer's closure reads its state when it runs, so every action it makes does the same thing
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// Pushes a screen onto the current tab's navigation stack (for a card that resolves its details before it opens them)
    @Entry var tvOpen = TVOpenAction { _ in }
}

extension View {
    /// The screens a tab's navigation stack pushes for its routes
    func tvRouteDestinations(connection: JellyfinConnection, apiClient: APIClient) -> some View {
        navigationDestination(for: TVRoute.self) { route in
            switch route {
            case .title(.movie(let id), let poster):
                TVMovieDetailsView(connection: connection, apiClient: apiClient, id: id, libraryPoster: poster)
            case .title(.series(let id), let poster):
                TVSeriesDetailsView(connection: connection, apiClient: apiClient, id: id, libraryPoster: poster)
            case .episode(let series, let season, let episode):
                TVEpisodeDetailsView(connection: connection, apiClient: apiClient, seriesID: series, seasonNumber: season, episodeNumber: episode)
            case .collection(let item):
                TVCollectionView(connection: connection, collection: item)
            case .person(let id):
                TVPersonDetailsView(apiClient: apiClient, id: id)
            case .game(let id):
                TVGameDetailsView(apiClient: apiClient, id: id)
            }
        }
    }
}
