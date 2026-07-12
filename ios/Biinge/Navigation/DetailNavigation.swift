import SwiftUI

/// Episodes are pushed within a NavigationStack; movies, series, and people are
/// presented as modal sheets (see `presentsDetails`).
enum DetailRoute: Hashable {
    case episode(showId: Int, seasonNumber: Int, episodeNumber: Int)
}

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

extension EnvironmentValues {
    var apiClient: APIClient? {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }

    /// Presents a movie detail as a modal sheet.
    var presentMovie: @MainActor (Int) -> Void {
        get { self[PresentMovieKey.self] }
        set { self[PresentMovieKey.self] = newValue }
    }

    /// Presents a series detail as a modal sheet.
    var presentSeries: @MainActor (Int) -> Void {
        get { self[PresentSeriesKey.self] }
        set { self[PresentSeriesKey.self] = newValue }
    }

    /// Presents a person detail as a modal sheet.
    var presentPerson: @MainActor (Int) -> Void {
        get { self[PresentPersonKey.self] }
        set { self[PresentPersonKey.self] = newValue }
    }
}

extension View {
    /// Registers the push destinations (episodes) on a NavigationStack.
    func detailDestinations() -> some View {
        navigationDestination(for: DetailRoute.self) { route in
            switch route {
            case .episode(let showId, let seasonNumber, let episodeNumber):
                EpisodeDetailView(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            }
        }
    }

    /// Enables `presentMovie` / `presentSeries` / `presentPerson` for the subtree
    /// and presents those details as modal sheets. Applied recursively inside each
    /// sheet so nested navigation (a show's cast, a person's films) stacks correctly.
    func presentsDetails() -> some View {
        modifier(PresentsDetailsModifier())
    }
}

private struct DetailSheetItem: Identifiable {
    let id: Int
}

private struct PresentsDetailsModifier: ViewModifier {
    @State private var movie: DetailSheetItem?
    @State private var series: DetailSheetItem?
    @State private var person: DetailSheetItem?

    func body(content: Content) -> some View {
        content
            .environment(\.presentMovie) { movie = DetailSheetItem(id: $0) }
            .environment(\.presentSeries) { series = DetailSheetItem(id: $0) }
            .environment(\.presentPerson) { person = DetailSheetItem(id: $0) }
            .sheet(item: $movie) { item in
                sheetStack { MovieDetailView(movieId: item.id) }
            }
            .sheet(item: $series) { item in
                sheetStack { TvDetailView(seriesId: item.id) }
            }
            .sheet(item: $person) { item in
                sheetStack { PersonDetailView(personId: item.id) }
            }
    }

    private func sheetStack<Detail: View>(@ViewBuilder _ detail: () -> Detail) -> some View {
        NavigationStack {
            detail().detailDestinations()
        }
        .presentationDragIndicator(.hidden)
        .presentsDetails()
    }
}
