import SwiftUI

/// The search panel over the Mac window: a field with a clear button over the biinge catalog's Movies, TV Shows and People that the arrow keys and Return pick, with the recent searches, prompt, no results and error states
struct DesktopSearchView: View {
    let apiClient: APIClient
    /// Bumped by each Search or Find shortcut, which focuses the field again
    let focusRequest: Int
    /// Opens the picked result's details or person page (the root view closes the overlay with it)
    let open: (DesktopRoute) -> Void
    let close: () -> Void

    @State private var query = ""
    /// The last finished search: its term, then up to 5 movies, 3 shows and 3 people in their non-empty groups (kept while the next one runs, so the panel doesn't flicker)
    @State private var results: (term: String, groups: [(title: String, hits: [Hit])])?
    /// The current query's error message
    @State private var failure: String?
    /// The highlighted row's index across the groups in order
    @State private var selection = 0
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @FocusState private var isFieldFocused: Bool
    @AppStorage(RecentSearches.storageKey) private var recents = RecentSearches()

    /// A result row (one shape for the three groups, so the arrow keys walk them as one list)
    private struct Hit {
        let route: DesktopRoute
        let name: String
        let detail: String
        let imagePath: String
        let isPerson: Bool
    }

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = results?.groups.flatMap(\.hits) ?? []
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(spacing: 0) {
                field(rows: rows)
                Divider()
                content(term: term, rows: rows)
                Divider()
                HStack(spacing: 18) {
                    Text("↑↓ to move")
                    Text("↩ to open")
                    Text("esc to close")
                    Spacer()
                }
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .frame(height: 40)
            }
            .frame(maxWidth: 760)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 50, y: 20)
            .padding(.horizontal, 24)
            .padding(.top, 86)
        }
        // set once the overlay is in the window, as a focus set in the transaction that inserts the field can be lost, and again on each shortcut
        .task(id: focusRequest) { isFieldFocused = true }
        // a new query cancels the search before it, and the search waits until typing has paused for 300 ms
        .task(id: term) {
            failure = nil
            guard !term.isEmpty else {
                results = nil
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(300))
                // one request per group, as on iPhone
                async let movies = apiClient.searchMovies(query: term)
                async let series = apiClient.searchSeries(query: term)
                async let people = apiClient.searchPeople(query: term)
                let (foundMovies, foundSeries, foundPeople) = try await (movies.data, series.data, people.data)
                // a newer query may have started while this one was in flight
                guard !Task.isCancelled else { return }
                let groups: [(title: String, hits: [Hit])] = [
                    ("Movies", foundMovies.prefix(5).map { movie in
                        let released = DetailFact.release(movie.releaseDate) ?? ""
                        return Hit(route: .title(.movie(movie.id)), name: movie.title, detail: released.isEmpty ? "Movie" : "Movie  ·  \(released)", imagePath: movie.posterPath, isPerson: false)
                    }),
                    ("TV Shows", foundSeries.prefix(3).map { seriesItem in
                        let released = DetailFact.release(seriesItem.releaseDate) ?? ""
                        return Hit(
                            route: .title(.series(seriesItem.id)), name: seriesItem.title,
                            detail: released.isEmpty ? "TV Show" : "TV Show  ·  \(released)", imagePath: seriesItem.posterPath, isPerson: false
                        )
                    }),
                    ("People", foundPeople.prefix(3).map { person in
                        Hit(route: .person(id: person.id), name: person.name, detail: "Person", imagePath: person.profilePath, isPerson: true)
                    }),
                ]
                results = (term: term, groups: groups.filter { !$0.hits.isEmpty })
                // the next first search's skeleton shows as many rows in each group, unless this one found nothing
                if groups.contains(where: { !$0.hits.isEmpty }) {
                    for group in groups { SkeletonRows.counts["search-\(group.title)"] = group.hits.count }
                }
                selection = 0
            } catch {
                // typing on or closing the overlay cancels the search, which is no failure
                guard !Task.isCancelled else { return }
                // the hidden old rows must not answer Return or the arrow keys
                results = nil
                failure = error.localizedDescription
            }
        }
    }

    /// The search field with the clear button and the esc chip, which also takes Escape
    private func field(rows: [Hit]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            TextField("Search movies, shows and people", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .autocorrectionDisabled()
                .focused($isFieldFocused)
                .onSubmit {
                    guard rows.indices.contains(selection) else { return }
                    recents.add(query)
                    open(rows[selection].route)
                }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    let step = press.key == .upArrow ? -1 : 1
                    selection = min(max(selection + step, 0), max(rows.count - 1, 0))
                    return .handled
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    isFieldFocused = true
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
            Button(action: close) {
                Text("esc")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            // a key equivalent reaches the window before the field editor, so Escape closes even while typing
            .keyboardShortcut(.cancelAction)
            .help("Close search (Esc)")
        }
        .padding(.leading, 22)
        .padding(.trailing, 20)
        .frame(height: 68)
    }

    /// The recent searches or the prompt before typing, the error, the results in their groups, the no results state, or a skeleton for the first search
    @ViewBuilder
    private func content(term: String, rows: [Hit]) -> some View {
        if term.isEmpty, !recents.terms.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    header("Recent Searches")
                    Spacer()
                    Button {
                        recents.clear()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(recents.terms, id: \.self) { recent in
                    Button {
                        query = recent
                        isFieldFocused = true
                    } label: {
                        Label(recent, systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        } else if term.isEmpty {
            message(icon: "magnifyingglass", title: "Search the Biinge catalog", text: "Find any movie, TV show or person, whether your server holds it or not.")
        } else if !isSkeletonHeld, let failure {
            message(icon: "exclamationmark.triangle", title: "Search failed", text: failure)
        } else if !isSkeletonHeld, let results {
            if rows.isEmpty {
                VStack(spacing: 10) {
                    message(
                        icon: "magnifyingglass",
                        title: "No results for “\(results.term)”",
                        text: "Search covers every movie, show and person in the Biinge catalog. Check the spelling, or try another name."
                    )
                    Button("Clear Search") {
                        query = ""
                        isFieldFocused = true
                    }
                    .padding(.bottom, 32)
                }
            } else {
                ScrollViewReader { proxy in
                    // a short list sits at the top under the field, and a long one scrolls
                    ViewThatFits(in: .vertical) {
                        groups(results.groups)
                        ScrollView {
                            groups(results.groups)
                        }
                    }
                    .frame(maxHeight: 600, alignment: .top)
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
            }
        } else {
            // each group as many rows as the last search returned, under its header as text
            VStack(alignment: .leading, spacing: 0) {
                ForEach(["Movies", "TV Shows", "People"], id: \.self) { title in
                    let isPerson = title == "People"
                    let count = SkeletonRows.count(for: "search-\(title)", screenful: title == "Movies" ? 5 : 3)
                    if count > 0 {
                        header(title)
                        ForEach(0..<count, id: \.self) { _ in
                            HStack(spacing: 14) {
                                SkeletonBlock(cornerRadius: isPerson ? 22 : 6)
                                    .frame(width: 44, height: isPerson ? 44 : 66)
                                    .frame(height: 66)
                                VStack(alignment: .leading, spacing: 8) {
                                    SkeletonBlock(cornerRadius: 4)
                                        .frame(width: 220, height: 16)
                                    SkeletonBlock(cornerRadius: 4)
                                        .frame(width: 120, height: 13)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(10)
            // up to the panel's height, as the results scroll past it
            .frame(maxWidth: .infinity, maxHeight: 600, alignment: .topLeading)
            .clipped()
            .loadingSkeleton(isHeld: $isSkeletonHeld)
        }
    }

    /// The groups in order, each under its header, numbering the rows across them
    private func groups(_ groups: [(title: String, hits: [Hit])]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups.indices, id: \.self) { group in
                let offset = groups[..<group].reduce(0) { $0 + $1.hits.count }
                header(groups[group].title)
                ForEach(groups[group].hits.indices, id: \.self) { index in
                    row(groups[group].hits[index], index: offset + index)
                        .rowFade(at: offset + index)
                }
            }
        }
        .padding(10)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    /// A result row: the poster or the round portrait, the name and the kind with the release; the pointer moves the highlight and a click opens it
    private func row(_ hit: Hit, index: Int) -> some View {
        let isSelected = index == selection
        let title: DetailsTitle? = if case .title(let title, _) = hit.route { title } else { nil }
        return Button {
            recents.add(query)
            open(hit.route)
        } label: {
            HStack(spacing: 14) {
                if hit.isPerson {
                    // greyscale, as the cast rows
                    CachedImage(url: Config.tmdbImageURL(path: hit.imagePath, size: "w185"), maxPixel: 88, grayscale: true) {
                        Color.biingeSecondaryCard
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .frame(width: 44, height: 66)
                } else {
                    PosterImage(title: "", cornerRadius: 0, poster: Config.tmdbImageURL(path: hit.imagePath, size: "w185"),
                                frame: CGSize(width: 44, height: 66), titleFont: .system(size: 14), titlePadding: 12)
                        // the full check would cover this 44 pt thumbnail
                        .trackedBadge(title, scale: 0.6)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.name)
                        .font(.system(size: 16.5, weight: .semibold))
                        .lineLimit(1)
                    Text(hit.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("Open ↩")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { selection = index } }
        .id(index)
    }

    /// The prompt, no results and error states: an icon over a title and a line of text
    private func message(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(text)
                .font(.system(size: 15.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
}
