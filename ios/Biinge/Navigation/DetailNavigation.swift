import SwiftUI

/// Movies, series, people, and episodes are all presented as modal sheets via
/// the `present*` environment actions (see `presentsDetails`).

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient? = nil
}

private struct PresentMovieKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int) -> Void = { _ in }
}

private struct PresentSeriesKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int) -> Void = { _ in }
}

private struct PresentPersonKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int) -> Void = { _ in }
}

private struct PresentEpisodeKey: EnvironmentKey {
    static let defaultValue: @MainActor (Int, Int, Int) -> Void = { _, _, _ in }
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

    var presentPerson: @MainActor (Int) -> Void {
        get { self[PresentPersonKey.self] }
        set { self[PresentPersonKey.self] = newValue }
    }

    /// Presents an episode detail as a modal sheet (showId, seasonNumber, episodeNumber).
    var presentEpisode: @MainActor (Int, Int, Int) -> Void {
        get { self[PresentEpisodeKey.self] }
        set { self[PresentEpisodeKey.self] = newValue }
    }
}

extension View {
    /// Enables the `present*` actions for the subtree and presents those details
    /// as modal sheets. Applied recursively inside each sheet so nested
    /// navigation (a show's cast, an episode, a person's films) stacks correctly.
    func presentsDetails() -> some View {
        modifier(PresentsDetailsModifier())
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
    @State private var movie: DetailSheetItem?
    @State private var series: DetailSheetItem?
    @State private var person: DetailSheetItem?
    @State private var episode: EpisodeSheetItem?

    func body(content: Content) -> some View {
        content
            .environment(\.presentMovie) { movie = DetailSheetItem(id: $0) }
            .environment(\.presentSeries) { series = DetailSheetItem(id: $0) }
            .environment(\.presentPerson) { person = DetailSheetItem(id: $0) }
            .environment(\.presentEpisode) { showId, seasonNumber, episodeNumber in
                episode = EpisodeSheetItem(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            }
            .sheet(item: $movie) { item in
                sheet { MovieDetailView(movieId: item.id) }.id(item.id)
            }
            .sheet(item: $series) { item in
                sheet { TvDetailView(seriesId: item.id) }.id(item.id)
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
