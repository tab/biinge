import SwiftUI

struct MobileSearchView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(GameStore.self) private var gameStore

    @State private var query = ""
    @State private var results = SearchResults()
    @State private var isLoading = false
    /// Bumped by Retry, which runs the load again
    @State private var attempt = 0
    @State private var didDeepLink = false
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(\.presentMovie) private var presentMovie
    @Environment(\.presentSeries) private var presentSeries
    @Environment(\.presentGame) private var presentGame
    @Environment(\.presentPerson) private var presentPerson

    private var isTrending: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var movies: [SearchMovie] { results.movies ?? [] }
    private var series: [SearchSeries] { results.series ?? [] }
    private var games: [SearchGame] { results.games ?? [] }
    private var people: [SearchPerson] { results.people ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !isSkeletonHeld, !isLoading, results.failed, !results.isEmpty {
                        ErrorBanner(message: "Some results didn’t load.") { attempt += 1 }
                    }
                    if !isSkeletonHeld, !movies.isEmpty {
                        DetailSection(title: "Movies") { moviesRow }
                    }
                    if !isSkeletonHeld, !series.isEmpty {
                        DetailSection(title: "TV Shows") { seriesRow }
                    }
                    if !isSkeletonHeld, !games.isEmpty {
                        DetailSection(title: "Games") { gamesRow }
                    }
                    if !isSkeletonHeld, !people.isEmpty {
                        DetailSection(title: "People") { peopleRow }
                    }
                    if isSkeletonHeld || (isLoading && results.isEmpty) {
                        // with nothing on screen, each section as many cards as its last load returned, under its title as text
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(["Movies", "TV Shows", "Games", "People"], id: \.self) { title in
                                let isPeople = title == "People"
                                let count = SkeletonRows.count(for: "search-\(title)", screenful: isPeople ? 4 : 3)
                                if count > 0 {
                                    DetailSection(title: title) {
                                        HStack(alignment: .top, spacing: isPeople ? 12 : 10) {
                                            ForEach(0..<count, id: \.self) { _ in
                                                if isPeople {
                                                    VStack(spacing: 6) {
                                                        SkeletonBlock(cornerRadius: 38)
                                                            .frame(width: 76, height: 76)
                                                        SkeletonBlock(cornerRadius: 4)
                                                            .frame(width: 60, height: 11)
                                                    }
                                                    .frame(width: 84)
                                                } else {
                                                    PosterSkeleton()
                                                        .frame(width: 120)
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .loadingSkeleton(isHeld: $isSkeletonHeld)
                    } else if isLoading {
                        // a new query's results load under the last ones, which stay on screen
                        ProgressView().tint(Color.biingeLoader)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else if results.failed, results.isEmpty {
                        // a failed load shows its error, never the no-results state
                        ContentUnavailableView {
                            Label(results.term.isEmpty ? "Couldn’t load Trending" : "Couldn’t search", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("Check your connection and try again.")
                        } actions: {
                            Button("Retry") { attempt += 1 }
                        }
                        .padding(.top, 60)
                    } else if results.isEmpty {
                        ContentUnavailableView(
                            results.term.isEmpty ? "No results" : "No results for “\(results.term)”",
                            systemImage: "magnifyingglass",
                            description: Text(results.term.isEmpty ? "Trending is unavailable." : "Try a different search.")
                        )
                        .padding(.top, 60)
                    }
                }
                // pinned to the scroll view's width, so the skeleton's cards run off the trailing edge as the loaded rows' do
                .containerRelativeFrame(.horizontal, alignment: .leading)
                .padding(.vertical)
            }
            .background(Color.biingeBackground)
            .navigationTitle(isTrending ? "Trending" : "Search")
            .searchable(text: $query, prompt: "Movies, shows, games, people")
        }
        .task(id: "\(query)-\(attempt)") { await run() }
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
                            .trackedBadge(.movie(movie.id))
                    }
                    .buttonStyle(.pressable)
                    .detailTransitionSource("movie-\(movie.id)")
                }
            }
            .padding(.horizontal)
        }
    }

    private var seriesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(series) { seriesItem in
                    Button {
                        presentSeries(seriesItem.id)
                    } label: {
                        PosterImage(path: seriesItem.posterPath, title: seriesItem.title, size: "w342")
                            .frame(width: 120)
                            .trackedBadge(.series(seriesItem.id))
                    }
                    .buttonStyle(.pressable)
                    .detailTransitionSource("series-\(seriesItem.id)")
                }
            }
            .padding(.horizontal)
        }
    }

    private var gamesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(games) { game in
                    Button {
                        presentGame(game.id)
                    } label: {
                        PosterImage(path: game.posterPath, title: game.title, source: .igdb, size: "cover_big_2x")
                            .frame(width: 120)
                            .overlay(alignment: .topLeading) {
                                if gameStore.currentState(id: game.id) != nil { WatchedBadge() }
                            }
                    }
                    .buttonStyle(.pressable)
                    .detailTransitionSource("game-\(game.id)")
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
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal)
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
        async let g = try? await apiClient.trendingGames().data
        async let p = try? await apiClient.trendingPeople().data
        let (loadedMovies, loadedSeries, loadedGames, loadedPeople) = await (m, s, g, p)
        // a cancelled task (typing) must not wipe the visible results with empties
        guard !Task.isCancelled else { return }
        results = SearchResults(movies: loadedMovies, series: loadedSeries, games: loadedGames, people: loadedPeople)
        // the next loading skeleton shows as many of each, unless this load found nothing to show
        if !results.isEmpty {
            for (title, count) in [("Movies", movies.count), ("TV Shows", series.count), ("Games", games.count), ("People", people.count)] {
                SkeletonRows.counts["search-\(title)"] = count
            }
        }
        isLoading = false
    }

    private func runSearch(_ term: String) async {
        guard let apiClient else { return }
        isLoading = true
        async let m = try? await apiClient.searchMovies(query: term).data
        async let s = try? await apiClient.searchSeries(query: term).data
        async let g = try? await apiClient.searchGames(query: term).data
        async let p = try? await apiClient.searchPeople(query: term).data
        let (loadedMovies, loadedSeries, loadedGames, loadedPeople) = await (m, s, g, p)
        guard !Task.isCancelled else { return }
        results = SearchResults(term: term, movies: loadedMovies, series: loadedSeries, games: loadedGames, people: loadedPeople)
        // the next loading skeleton shows as many of each, unless this load found nothing to show
        if !results.isEmpty {
            for (title, count) in [("Movies", movies.count), ("TV Shows", series.count), ("Games", games.count), ("People", people.count)] {
                SkeletonRows.counts["search-\(title)"] = count
            }
        }
        isLoading = false
    }
}
