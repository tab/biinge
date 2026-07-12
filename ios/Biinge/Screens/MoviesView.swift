import SwiftUI

struct MoviesView: View {
    let store: MovieStore
    @State private var selection: Segment = .want
    @State private var path: [DetailRoute] = []

    enum Segment: String, CaseIterable {
        case want = "Want"
        case watched = "Watched"
    }

    private var movies: [LibraryMovie] {
        selection == .want ? store.wantMovies : store.watchedMovies
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("", selection: $selection) {
                    ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                content
            }
            .navigationTitle("Movies")
            .detailDestinations()
        }
        .task {
            await store.loadIfNeeded()
            #if DEBUG
            if path.isEmpty, let raw = ProcessInfo.processInfo.environment["DEBUG_MOVIE_ID"], let id = Int(raw) {
                path = [.movie(id: id)]
            }
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && !store.hasLoaded {
            ProgressView().tint(Color.biingePrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if movies.isEmpty {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "film",
                description: Text("Movies you add will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PosterGrid(items: movies) { movie in
                NavigationLink(value: DetailRoute.movie(id: movie.id)) {
                    PosterImage(path: movie.posterPath, title: movie.title)
                        .overlay(alignment: .topTrailing) {
                            if movie.pinned { PinBadge() }
                        }
                }
                .buttonStyle(.plain)
            }
            .refreshable { await store.load() }
        }
    }
}
