import SwiftUI

/// Value-based routes for pushing detail screens within a tab's NavigationStack.
enum DetailRoute: Hashable {
    case movie(id: Int)
    case series(id: Int)
    case person(id: Int)
    case episode(showId: Int, seasonNumber: Int, episodeNumber: Int)
}

/// A movie presented as a modal sheet (from a library grid or search).
struct MoviePresentation: Identifiable {
    let id: Int
}

extension View {
    /// Presents a movie detail as a modal sheet, matching the RN app.
    func movieSheet(_ item: Binding<MoviePresentation?>) -> some View {
        sheet(item: item) { presentation in
            NavigationStack {
                MovieDetailView(movieId: presentation.id)
                    .detailDestinations()
            }
            .presentationDragIndicator(.hidden)
        }
    }
}

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient? = nil
}

extension EnvironmentValues {
    var apiClient: APIClient? {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

extension View {
    /// Registers every detail destination on a NavigationStack so cross-links
    /// (recommendations, cast, episodes) resolve within the same stack.
    func detailDestinations() -> some View {
        navigationDestination(for: DetailRoute.self) { route in
            switch route {
            case .movie(let id):
                MovieDetailView(movieId: id)
            case .series(let id):
                TvDetailView(seriesId: id)
            case .person(let id):
                PersonDetailView(personId: id)
            case .episode(let showId, let seasonNumber, let episodeNumber):
                EpisodeDetailView(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            }
        }
    }
}
