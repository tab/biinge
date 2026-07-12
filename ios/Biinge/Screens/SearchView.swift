import SwiftUI

struct SearchView: View {
    @Environment(\.apiClient) private var apiClient

    @State private var query = ""
    @State private var movies: [SearchMovie] = []
    @State private var series: [SearchSeries] = []
    @State private var people: [SearchPerson] = []
    @State private var isLoading = false
    @State private var path: [DetailRoute] = []

    private var isTrending: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isEmpty: Bool { movies.isEmpty && series.isEmpty && people.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
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
                        ProgressView().tint(Color.biingePrimary)
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
            .detailDestinations()
        }
        .searchable(text: $query, prompt: "Movies, shows, people")
        .task(id: query) { await run() }
    }

    private var moviesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(movies) { movie in
                    NavigationLink(value: DetailRoute.movie(id: movie.id)) {
                        PosterImage(path: movie.posterPath, title: movie.title, size: "w185")
                            .frame(width: 120)
                            .overlay(alignment: .topTrailing) { inLibraryBadge(movie.state) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var seriesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(series) { show in
                    NavigationLink(value: DetailRoute.series(id: show.id)) {
                        PosterImage(path: show.posterPath, title: show.title, size: "w185")
                            .frame(width: 120)
                            .overlay(alignment: .topTrailing) { inLibraryBadge(show.state) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var peopleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(people) { person in
                    NavigationLink(value: DetailRoute.person(id: person.id)) {
                        VStack(spacing: 6) {
                            ProfileCircle(path: person.profilePath, size: 76)
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

    @ViewBuilder
    private func inLibraryBadge(_ state: WatchState?) -> some View {
        if let state, state != .none {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.biingePrimary)
                .padding(5)
                .background(.black.opacity(0.5), in: Circle())
                .padding(5)
        }
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
        movies = await m ?? []
        series = await s ?? []
        people = await p ?? []
        isLoading = false
    }

    private func runSearch(_ term: String) async {
        guard let apiClient else { return }
        isLoading = true
        async let m = try? await apiClient.searchMovies(query: term).data
        async let s = try? await apiClient.searchSeries(query: term).data
        async let p = try? await apiClient.searchPeople(query: term).data
        movies = await m ?? []
        series = await s ?? []
        people = await p ?? []
        isLoading = false
    }
}
