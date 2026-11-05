import SwiftUI

/// The Search tab: the system keyboard over Movies, TV Shows and People rows from the biinge catalog, with the recent searches, prompt, no results and offline states
struct TVSearchView: View {
    let apiClient: APIClient

    @State private var query = ""
    /// The current query's movies, shows and people, nil while its search is out
    @State private var results: (movies: [SearchMovie], series: [SearchSeries], people: [SearchPerson])?
    /// The current query's error message
    @State private var failure: String?
    /// Bumped by Try Again to run the same query again
    @State private var attempt = 0
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @AppStorage(RecentSearches.storageKey) private var recents = RecentSearches()
    @Environment(\.tvOpen) private var open

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if term.isEmpty, !recents.terms.isEmpty {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Recent Searches")
                        .font(.system(size: 40, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Color.biingeText.opacity(0.7))
                        .padding(.leading, 96)
                    ScrollView(.horizontal) {
                        HStack(spacing: 22) {
                            ForEach(recents.terms, id: \.self) { recent in
                                Button { query = recent } label: {
                                    Label(recent, systemImage: "clock.arrow.circlepath")
                                }
                            }
                            Button { recents.clear() } label: {
                                Label("Clear", systemImage: "xmark")
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        .padding(.horizontal, 96)
                        .padding(.vertical, 24)
                    }
                    .scrollClipDisabled()
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 40)
                .focusSection()
                .ignoresSafeArea(edges: .horizontal)
            } else if term.isEmpty {
                message(icon: "magnifyingglass", title: "Search the Biinge catalog", text: "Find any movie, TV show or person, whether your server holds it or not.")
            } else if !isSkeletonHeld, let failure {
                Message(icon: "icloud.slash", title: "Can’t reach Biinge", text: failure, action: "Try Again") {
                    attempt += 1
                }
            } else if !isSkeletonHeld, let results {
                if results.movies.isEmpty && results.series.isEmpty && results.people.isEmpty {
                    message(icon: "magnifyingglass", title: "No results for “\(term)”", text: "Search covers every movie, show and person in the Biinge catalog. Try another spelling or name.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 72) {
                            row("Movies", count: results.movies.count) {
                                ForEach(results.movies) { movie in
                                    Button { pick(.title(.movie(movie.id)), term: term) } label: {
                                        PosterImage(title: movie.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: movie.posterPath, size: "w500"),
                                                    frame: CGSize(width: 220, height: 330), titleFont: .system(size: 26), titlePadding: 20)
                                            .trackedBadge(.movie(movie.id))
                                    }
                                    .buttonStyle(TVCardButtonStyle(width: 220, height: 330, cornerRadius: 16, title: movie.title, subtitle: DetailFact.release(movie.releaseDate) ?? ""))
                                }
                            }
                            row("TV Shows", count: results.series.count) {
                                ForEach(results.series) { seriesItem in
                                    Button { pick(.title(.series(seriesItem.id)), term: term) } label: {
                                        PosterImage(title: seriesItem.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: seriesItem.posterPath, size: "w500"),
                                                    frame: CGSize(width: 220, height: 330), titleFont: .system(size: 26), titlePadding: 20)
                                            .trackedBadge(.series(seriesItem.id))
                                    }
                                    .buttonStyle(TVCardButtonStyle(width: 220, height: 330, cornerRadius: 16, title: seriesItem.title, subtitle: DetailFact.release(seriesItem.releaseDate) ?? ""))
                                }
                            }
                            row("People", count: results.people.count) {
                                ForEach(results.people) { person in
                                    let initials = person.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
                                    Button { pick(.person(id: person.id), term: term) } label: {
                                        // black-and-white portraits, as the cast rows (the placeholder is already grey)
                                        PosterImage(title: initials, cornerRadius: 0, poster: Config.tmdbImageURL(path: person.profilePath, size: "w185"),
                                                    frame: CGSize(width: 200, height: 200), titleFont: .system(size: 26), titlePadding: 20)
                                            .grayscale(1)
                                    }
                                    .buttonStyle(TVCardButtonStyle(width: 200, height: 200, cornerRadius: 100, title: person.name, subtitle: nil))
                                }
                            }
                        }
                        .padding(.top, 40)
                        .padding(.bottom, 72)
                    }
                    .ignoresSafeArea(edges: .horizontal)
                }
            } else {
                // each row as many cards as the last search returned, under its title as text
                ScrollView {
                    VStack(alignment: .leading, spacing: 72) {
                        ForEach(["Movies", "TV Shows", "People"], id: \.self) { title in
                            let isPerson = title == "People"
                            let count = SkeletonRows.count(for: "search-\(title)", screenful: 6)
                            if count > 0 {
                                VStack(alignment: .leading, spacing: 28) {
                                    Text(title)
                                        .font(.system(size: 40, weight: .semibold))
                                        .tracking(-0.8)
                                        .foregroundStyle(Color.biingeText.opacity(0.7))
                                        .padding(.leading, 96)
                                    HStack(alignment: .top, spacing: 48) {
                                        ForEach(0..<count, id: \.self) { _ in
                                            SkeletonBlock(cornerRadius: isPerson ? 100 : 16)
                                                .frame(width: isPerson ? 200 : 220, height: isPerson ? 200 : 330)
                                        }
                                    }
                                    .padding(.horizontal, 96)
                                }
                            }
                        }
                    }
                    .padding(.top, 40)
                }
                .scrollDisabled(true)
                .ignoresSafeArea(edges: .horizontal)
                .loadingSkeleton(isHeld: $isSkeletonHeld)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground.ignoresSafeArea())
        .searchable(text: $query, prompt: "Movies, shows and people")
        // the keyboard's Search key keeps the term as a recent search
        .onSubmit(of: .search) { recents.add(query) }
        // a new query cancels the search before it, and the search waits until typing has paused for 300 ms
        .task(id: "\(attempt) \(term)") {
            results = nil
            failure = nil
            guard !term.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                // one request per group, as on iPhone
                async let movies = apiClient.searchMovies(query: term)
                async let series = apiClient.searchSeries(query: term)
                async let people = apiClient.searchPeople(query: term)
                let found = try await (movies: movies.data, series: series.data, people: people.data)
                // a newer query may have started while this one was in flight
                guard !Task.isCancelled else { return }
                results = found
                // the next search's skeleton shows as many cards in each row, unless this one found nothing
                if !(found.movies.isEmpty && found.series.isEmpty && found.people.isEmpty) {
                    SkeletonRows.counts["search-Movies"] = found.movies.count
                    SkeletonRows.counts["search-TV Shows"] = found.series.count
                    SkeletonRows.counts["search-People"] = found.people.count
                }
            } catch {
                // typing on or leaving the tab cancels the search, which is no failure
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }

    /// Keeps the term as a recent search and opens the picked result
    private func pick(_ route: TVRoute, term: String) {
        recents.add(term)
        open(route)
    }

    /// A titled row of cards with its count that scrolls sideways with focus, left out when it has no cards
    @ViewBuilder
    private func row(_ title: String, count: Int, @ViewBuilder cards: () -> some View) -> some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(title)
                        .font(.system(size: 40, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Color.biingeText.opacity(0.7))
                    Text("\(count)")
                        .font(.system(size: 29))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                }
                .padding(.leading, 96)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 48) {
                        cards()
                    }
                    .padding(.horizontal, 96)
                }
                .scrollClipDisabled()
            }
            .focusSection()
        }
    }

    /// The prompt and no results states in the look of `Message`, without its action
    private func message(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.biingeAccent)
                .frame(width: 110, height: 110)
                .background(Color.biingeAccent.opacity(0.16), in: Circle())
            Text(title)
                .font(.system(size: 72, weight: .bold))
                .tracking(-2.16)
            Text(text)
                .font(.system(size: 30))
                .lineSpacing(7)
                .foregroundStyle(Color.biingeText.opacity(0.7))
                .frame(maxWidth: 1000)
        }
        .multilineTextAlignment(.center)
    }
}
