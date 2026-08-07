import SwiftUI

struct SearchView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(MovieStore.self) private var movieStore
    @Environment(TvStore.self) private var tvStore

    @State private var query = ""
    @State private var movies: [SearchMovie] = []
    @State private var series: [SearchSeries] = []
    @State private var people: [SearchPerson] = []
    @State private var isLoading = false
    @State private var didDeepLink = false
    @Environment(\.presentMovie) private var presentMovie
    @Environment(\.presentSeries) private var presentSeries
    @Environment(\.presentPerson) private var presentPerson

    private var isTrending: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isEmpty: Bool { movies.isEmpty && series.isEmpty && people.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !movies.isEmpty {
                        DetailSection(title: "Movies") { moviesRow }
                    }
                    if !series.isEmpty {
                        DetailSection(title: "TV Shows") { seriesRow }
                    }
                    if !people.isEmpty {
                        DetailSection(title: "People") { peopleRow }
                    }
                    if isLoading {
                        ProgressView().tint(Color.biingeLoader)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else if isEmpty {
                        ContentUnavailableView(
                            "No results",
                            systemImage: "magnifyingglass",
                            description: Text(isTrending ? "Trending is unavailable." : "Try a different search.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.biingeBackground)
            .navigationTitle(isTrending ? "Trending" : "Search")
            .searchable(text: $query, prompt: "Movies, shows, people")
        }
        .task(id: query) { await run() }
        .task {
            #if DEBUG
            if !didDeepLink, let raw = ProcessInfo.processInfo.environment["DEBUG_PERSON_ID"], let id = Int(raw) {
                didDeepLink = true
                presentPerson(id)
            }
            #endif
        }
    }

    private var moviesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(movies) { movie in
                    Button {
                        presentMovie(movie.id)
                    } label: {
                        PosterImage(path: movie.posterPath, title: movie.title, size: "w342")
                            .frame(width: 120)
                            .overlay(alignment: .topLeading) {
                                if isTrackedMovie(movie.id, snapshot: movie.state) { WatchedBadge() }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var seriesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(series) { show in
                    Button {
                        presentSeries(show.id)
                    } label: {
                        PosterImage(path: show.posterPath, title: show.title, size: "w342")
                            .frame(width: 120)
                            .overlay(alignment: .topLeading) {
                                if isTrackedSeries(show.id, snapshot: show.state) { WatchedBadge() }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var peopleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(people) { person in
                    Button {
                        presentPerson(person.id)
                    } label: {
                        VStack(spacing: 6) {
                            ProfileCircle(path: person.profilePath, size: 76, grayscale: true)
                            Text(person.name)
                                .font(.biingeCaption2).foregroundStyle(.primary)
                                .lineLimit(1).frame(width: 84)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    /// Live store membership, with the response's snapshot as fallback until the library loads
    private func isTrackedMovie(_ id: Int, snapshot: WatchState?) -> Bool {
        movieStore.currentState(id: id) != nil
            || (!movieStore.hasLoaded && (snapshot ?? WatchState.none) != WatchState.none)
    }

    private func isTrackedSeries(_ id: Int, snapshot: WatchState?) -> Bool {
        tvStore.currentState(id: id) != nil
            || (!tvStore.hasLoaded && (snapshot ?? WatchState.none) != WatchState.none)
    }

    private func run() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            await loadTrending()
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        await runSearch(trimmed)
    }

    private func loadTrending() async {
        guard let apiClient else { return }
        isLoading = true
        async let m = try? await apiClient.trendingMovies().data
        async let s = try? await apiClient.trendingSeries().data
        async let p = try? await apiClient.trendingPeople().data
        let (loadedMovies, loadedSeries, loadedPeople) = await (m, s, p)
        // a cancelled task (typing) must not wipe the visible results with empties
        guard !Task.isCancelled else { return }
        movies = loadedMovies ?? []
        series = loadedSeries ?? []
        people = loadedPeople ?? []
        isLoading = false
    }

    private func runSearch(_ term: String) async {
        guard let apiClient else { return }
        isLoading = true
        async let m = try? await apiClient.searchMovies(query: term).data
        async let s = try? await apiClient.searchSeries(query: term).data
        async let p = try? await apiClient.searchPeople(query: term).data
        let (loadedMovies, loadedSeries, loadedPeople) = await (m, s, p)
        guard !Task.isCancelled else { return }
        movies = loadedMovies ?? []
        series = loadedSeries ?? []
        people = loadedPeople ?? []
        isLoading = false
    }
}
