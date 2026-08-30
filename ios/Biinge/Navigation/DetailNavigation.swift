import SwiftUI

/// Movies, series, games, people, and episodes are presented as modal sheets via the present* actions

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient? = nil
}

private struct PresentMovieKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int) -> Void = { _ in }
}

private struct PresentSeriesKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int) -> Void = { _ in }
}

private struct PresentGameKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int) -> Void = { _ in }
}

private struct PresentPersonKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int) -> Void = { _ in }
}

private struct PresentEpisodeKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int, Int, Int) -> Void = { _, _, _ in }
}

private struct DetailNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var apiClient: APIClient? {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }

    var presentMovie: @MainActor (Int) -> Void {
        get { self[PresentMovieKey.self] }
        set { self[PresentMovieKey.self] = newValue }
    }

    var presentSeries: @MainActor (Int) -> Void {
        get { self[PresentSeriesKey.self] }
        set { self[PresentSeriesKey.self] = newValue }
    }

    var presentGame: @MainActor (Int) -> Void {
        get { self[PresentGameKey.self] }
        set { self[PresentGameKey.self] = newValue }
    }

    var presentPerson: @MainActor (Int) -> Void {
        get { self[PresentPersonKey.self] }
        set { self[PresentPersonKey.self] = newValue }
    }

    /// Presents an episode detail as a modal sheet (showId, seasonNumber, episodeNumber)
    var presentEpisode: @MainActor (Int, Int, Int) -> Void {
        get { self[PresentEpisodeKey.self] }
        set { self[PresentEpisodeKey.self] = newValue }
    }

    /// The namespace detail sheets zoom out of, published by `presentsDetails()`
    var detailNamespace: Namespace.ID? {
        get { self[DetailNamespaceKey.self] }
        set { self[DetailNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Enables the present* actions for the subtree, applied recursively inside each sheet
    func presentsDetails() -> some View {
        modifier(PresentsDetailsModifier())
    }

    /// Marks this cell as the source its detail sheet grows out of and shrinks back into
    func detailTransitionSource(_ id: String) -> some View {
        modifier(DetailTransitionSourceModifier(id: id))
    }
}

private struct DetailTransitionSourceModifier: ViewModifier {
    let id: String
    @Environment(\.detailNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct DetailSheetItem: Identifiable {
    let id: Int
}

private struct EpisodeSheetItem: Identifiable {
    let showId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    var id: String { "\(showId)-\(seasonNumber)-\(episodeNumber)" }
}

private struct PresentsDetailsModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    /// One namespace per level: a sheet's own sources belong to the nested modifier, not this one
    @Namespace private var namespace
    @State private var movie: DetailSheetItem?
    @State private var series: DetailSheetItem?
    @State private var game: DetailSheetItem?
    @State private var person: DetailSheetItem?
    @State private var episode: EpisodeSheetItem?

    func body(content: Content) -> some View {
        content
            .environment(\.detailNamespace, namespace)
            .environment(\.presentMovie) { movie = DetailSheetItem(id: $0) }
            .environment(\.presentSeries) { series = DetailSheetItem(id: $0) }
            .environment(\.presentGame) { game = DetailSheetItem(id: $0) }
            .environment(\.presentPerson) { person = DetailSheetItem(id: $0) }
            .environment(\.presentEpisode) { showId, seasonNumber, episodeNumber in
                episode = EpisodeSheetItem(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            }
            .sheet(item: $movie) { item in
                sheet { MovieDetailView(movieId: item.id) }
                    .id(item.id)
                    .navigationTransition(.zoom(sourceID: "movie-\(item.id)", in: namespace))
            }
            .sheet(item: $series) { item in
                sheet { TvDetailView(seriesId: item.id) }
                    .id(item.id)
                    .navigationTransition(.zoom(sourceID: "series-\(item.id)", in: namespace))
            }
            .sheet(item: $game) { item in
                sheet { GameDetailView(gameId: item.id) }
                    .id(item.id)
                    .navigationTransition(.zoom(sourceID: "game-\(item.id)", in: namespace))
            }
            .sheet(item: $person) { item in
                sheet { PersonDetailView(personId: item.id) }.id(item.id)
            }
            .sheet(item: $episode) { item in
                sheet {
                    EpisodeDetailView(showId: item.showId, seasonNumber: item.seasonNumber, episodeNumber: item.episodeNumber)
                }
                .id(item.id)
            }
    }

    private func sheet<Detail: View>(@ViewBuilder _ detail: () -> Detail) -> some View {
        NavigationStack {
            detail()
        }
        .preferredColorScheme(colorScheme)
        .presentationDragIndicator(.hidden)
        .presentsDetails()
    }
}
