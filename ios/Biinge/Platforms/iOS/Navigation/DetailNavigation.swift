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

private struct PresentTitleKey: EnvironmentKey {
    static let defaultValue: @MainActor (DetailsTitle, String?) -> Void = { _, _ in }
}

private struct PresentLibraryTitleKey: EnvironmentKey {
    static let defaultValue: @MainActor (DetailsTitle, String, URL?) -> Void = { _, _, _ in }
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

    /// Presents a movie's or a series' detail sheet by its TMDB ID, growing out of the cell marked with this source ID (nil for the title's own `detailTransitionSource(_:)`)
    var presentTitle: @MainActor (DetailsTitle, String?) -> Void {
        get { self[PresentTitleKey.self] }
        set { self[PresentTitleKey.self] = newValue }
    }

    /// Presents a movie's or a series' detail sheet from a Jellyfin tile, growing out of the cell marked with this source ID and showing this Jellyfin poster in place of the TMDB one (nil for the TMDB poster)
    var presentLibraryTitle: @MainActor (DetailsTitle, String, URL?) -> Void {
        get { self[PresentLibraryTitleKey.self] }
        set { self[PresentLibraryTitleKey.self] = newValue }
    }

    var presentGame: @MainActor (Int) -> Void {
        get { self[PresentGameKey.self] }
        set { self[PresentGameKey.self] = newValue }
    }

    var presentPerson: @MainActor (Int) -> Void {
        get { self[PresentPersonKey.self] }
        set { self[PresentPersonKey.self] = newValue }
    }

    /// Presents an episode detail as a modal sheet (seriesId, seasonNumber, episodeNumber)
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

    /// Marks this cell as the source a movie's or a series' detail sheet grows out of and shrinks back into
    func detailTransitionSource(_ title: DetailsTitle) -> some View {
        detailTransitionSource(title.sourceID)
    }
}

private extension DetailsTitle {
    /// The source ID of the title's own cell (a row that can repeat a title, such as Recently Added over the full grid, names its cells itself)
    var sourceID: String {
        switch self {
        case .movie(let id): "movie-\(id)"
        case .series(let id): "series-\(id)"
        }
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
    /// The ID of the cell the sheet grows out of
    let source: String
    /// The Jellyfin poster of the tile the sheet opened from, which the details show in place of the TMDB poster
    var poster: URL?
}

private struct EpisodeSheetItem: Identifiable {
    let seriesId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    var id: String { "\(seriesId)-\(seasonNumber)-\(episodeNumber)" }
}

private struct PresentsDetailsModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .environment(\.presentMovie) { movie = DetailSheetItem(id: $0, source: DetailsTitle.movie($0).sourceID) }
            .environment(\.presentSeries) { series = DetailSheetItem(id: $0, source: DetailsTitle.series($0).sourceID) }
            .environment(\.presentTitle) { title, source in
                switch title {
                case .movie(let id): movie = DetailSheetItem(id: id, source: source ?? title.sourceID)
                case .series(let id): series = DetailSheetItem(id: id, source: source ?? title.sourceID)
                }
            }
            .environment(\.presentLibraryTitle) { title, source, poster in
                switch title {
                case .movie(let id): movie = DetailSheetItem(id: id, source: source, poster: poster)
                case .series(let id): series = DetailSheetItem(id: id, source: source, poster: poster)
                }
            }
            .environment(\.presentGame) { game = DetailSheetItem(id: $0, source: "game-\($0)") }
            // a person's sheet slides up without a zoom
            .environment(\.presentPerson) { person = DetailSheetItem(id: $0, source: "") }
            .environment(\.presentEpisode) { seriesId, seasonNumber, episodeNumber in
                episode = EpisodeSheetItem(seriesId: seriesId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            }
            // each sheet grows out of its source cell and shrinks back on close, and Reduce Motion leaves the system sheet
            .sheet(item: $movie) { item in
                let detail = sheet { MobileMovieDetailsView(movieId: item.id, libraryPoster: item.poster) }.id(item.id)
                if reduceMotion { detail } else { detail.navigationTransition(.zoom(sourceID: item.source, in: namespace)) }
            }
            .sheet(item: $series) { item in
                let detail = sheet { MobileSeriesDetailsView(seriesId: item.id, libraryPoster: item.poster) }.id(item.id)
                if reduceMotion { detail } else { detail.navigationTransition(.zoom(sourceID: item.source, in: namespace)) }
            }
            .sheet(item: $game) { item in
                let detail = sheet { MobileGameDetailsView(gameId: item.id) }.id(item.id)
                if reduceMotion { detail } else { detail.navigationTransition(.zoom(sourceID: item.source, in: namespace)) }
            }
            .sheet(item: $person) { item in
                sheet { MobilePersonDetailsView(personId: item.id) }.id(item.id)
            }
            .sheet(item: $episode) { item in
                sheet {
                    MobileEpisodeDetailsView(seriesId: item.seriesId, seasonNumber: item.seasonNumber, episodeNumber: item.episodeNumber)
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
