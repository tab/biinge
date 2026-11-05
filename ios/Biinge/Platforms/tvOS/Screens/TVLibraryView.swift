import JellyfinAPI
import SwiftUI

/// The Movies or TV Shows tab: the library's title and count, the played, Genre and Sort menus over a paged poster grid
struct TVLibraryView: View {
    let connection: JellyfinConnection
    /// Movies, otherwise TV Shows
    let isMovies: Bool

    @State private var sort = LibrarySort.title
    @State private var filter = LibraryFilter.all
    /// The genre the grid narrows to, nil for every genre
    @State private var genre: String?
    @State private var genres: PagedLibrary.Genres

    init(connection: JellyfinConnection, isMovies: Bool) {
        self.connection = connection
        self.isMovies = isMovies
        _genres = State(initialValue: PagedLibrary.Genres(connection: connection, type: isMovies ? .movie : .series))
    }

    var body: some View {
        let filters: [(LibraryFilter, String)] = [(.all, "All"), (.unwatched, "Unwatched"), (.watched, "Watched")]
        let sorts: [(LibrarySort, String)] = [(.title, "Title"), (.recentlyAdded, "Date Added"), (.releaseYear, "Year")]
        let isNarrowed = filter != .all || genre != nil
        TVPagedGrid(
            connection: connection,
            list: isMovies ? .movies(sort, filter, genre: genre) : .series(sort, filter, genre: genre),
            columns: 6,
            columnWidth: 260,
            empty: isNarrowed
                ? (isMovies ? "No matching movies" : "No matching shows", "Nothing in your library matches this filter.")
                : isMovies
                ? ("No movies yet", "Add movies to your Jellyfin server’s Movies library.")
                : ("No shows yet", "Add shows to your Jellyfin server’s TV Shows library."),
            emptyAction: isNarrowed ? ("Show All", {
                filter = .all
                genre = nil
            }) : nil,
            skeleton: PosterSkeleton(cornerRadius: 16, caption: 29)
        ) { _, total in
            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(isMovies ? "Movies" : "TV Shows")
                        .font(.system(size: 76, weight: .bold))
                        .tracking(76 * -0.03)
                    Text(isMovies ? (total == 1 ? "1 movie" : "\(total) movies") : (total == 1 ? "1 show" : "\(total) shows"))
                        .font(.system(size: 29))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                }
                HStack(spacing: 24) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(filters, id: \.0) { option, label in
                                Text(label).tag(option)
                            }
                        }
                    } label: {
                        Label(filters.first { $0.0 == filter }?.1 ?? "", systemImage: "line.3.horizontal.decrease")
                    }
                    if !genres.names.isEmpty {
                        Menu {
                            Picker("Genre", selection: $genre) {
                                Text("All Genres").tag(String?.none)
                                ForEach(genres.names, id: \.self) { name in
                                    Text(name).tag(String?.some(name))
                                }
                            }
                        } label: {
                            Label(genre ?? "All Genres", systemImage: "theatermasks")
                        }
                    } else if genres.failed {
                        Button { Task { await genres.load() } } label: {
                            Label("Genres unavailable · Retry", systemImage: "exclamationmark.triangle")
                        }
                    }
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(sorts, id: \.0) { option, label in
                                Text(label).tag(option)
                            }
                        }
                    } label: {
                        Label(sorts.first { $0.0 == sort }?.1 ?? "", systemImage: "arrow.up.arrow.down")
                    }
                }
                .focusSection()
            }
        } cell: { item in
            TVPosterCard(connection: connection, item: item)
        }
        // a new sort, filter or genre starts the grid again from its first page
        .id(sort)
        .id(filter)
        .id(genre)
        .task { await genres.load() }
    }
}

/// A paged grid of one Jellyfin list under its header, with the loading, empty and offline states and a failed later page's Retry
struct TVPagedGrid<Header: View, Cell: View>: View {
    let connection: JellyfinConnection
    let columns: Int
    let columnWidth: CGFloat
    let columnSpacing: CGFloat
    /// The empty state's title and guidance
    let empty: (title: String, text: String)
    /// The empty state's action in place of Retry (a filter's Show All)
    var emptyAction: (label: String, perform: () -> Void)?
    /// The card the first page's skeleton repeats over two rows, nil for a spinner (a grid whose cells aren't posters)
    var skeleton: PosterSkeleton?
    /// The header over the grid, given the loaded items and the list's total
    let header: ([BaseItemDto], Int) -> Header
    let cell: (BaseItemDto) -> Cell

    @State private var library: PagedLibrary
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false

    init(
        connection: JellyfinConnection,
        list: LibraryList,
        columns: Int,
        columnWidth: CGFloat,
        columnSpacing: CGFloat = 36,
        empty: (title: String, text: String),
        emptyAction: (label: String, perform: () -> Void)? = nil,
        skeleton: PosterSkeleton? = nil,
        @ViewBuilder header: @escaping ([BaseItemDto], Int) -> Header,
        @ViewBuilder cell: @escaping (BaseItemDto) -> Cell
    ) {
        self.connection = connection
        self.columns = columns
        self.columnWidth = columnWidth
        self.columnSpacing = columnSpacing
        self.empty = empty
        self.emptyAction = emptyAction
        self.skeleton = skeleton
        self.header = header
        self.cell = cell
        _library = State(initialValue: PagedLibrary(connection: connection, list: list))
    }

    var body: some View {
        let items = library.items
        let total = library.total
        Group {
            if !isSkeletonHeld, let total, total > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 56) {
                        header(items, total)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(columnWidth), spacing: columnSpacing), count: columns), alignment: .leading, spacing: 72) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                cell(item)
                                    .environment(\.posterFadeIndex, index)
                                    .onAppear {
                                        // focus reaching the last two rows loads the next page
                                        if index >= items.count - 2 * columns { Task { await library.loadMore() } }
                                    }
                            }
                        }
                        if let pageFailure = library.pageFailure {
                            HStack(spacing: 32) {
                                Label("Couldn’t load more. \(pageFailure.message)", systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 29))
                                    .foregroundStyle(Color(rgb: 0xFF8A8D))
                                Button {
                                    Task {
                                        if pageFailure.isFirstPage {
                                            await library.load()
                                        } else {
                                            await library.loadMore()
                                        }
                                    }
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(PillButtonStyle())
                                .disabled(library.isLoading)
                            }
                            .frame(maxWidth: .infinity)
                            .focusSection()
                        }
                    }
                    // the header lines up with the grid, which sits in the middle of the screen
                    .frame(width: CGFloat(columns) * columnWidth + CGFloat(columns - 1) * columnSpacing, alignment: .leading)
                    .padding(.top, 40)
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea(edges: .horizontal)
            } else if !isSkeletonHeld, total == 0 {
                if let emptyAction {
                    Message(
                        icon: "line.3.horizontal.decrease.circle",
                        title: empty.title,
                        text: empty.text,
                        action: emptyAction.label,
                        actionIcon: "line.3.horizontal.decrease",
                        perform: emptyAction.perform
                    )
                } else {
                    Message(icon: "film.stack", title: empty.title, text: empty.text, action: "Retry") { Task { await library.reload() } }
                }
            } else if !isSkeletonHeld, let failure = library.failure {
                Message(icon: "icloud.slash", title: "Can’t reach \(connection.serverURL?.host() ?? "the server")", text: failure, action: "Try Again") { Task { await library.reload() } }
            } else if let skeleton {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(columnWidth), spacing: columnSpacing), count: columns), alignment: .leading, spacing: 72) {
                    ForEach(0..<2 * columns, id: \.self) { _ in
                        skeleton
                    }
                }
                // clears about the library header's title and filter row, so the grid sits where a loaded page puts it
                .padding(.top, 40 + 190 + 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .loadingSkeleton(isHeld: $isSkeletonHeld)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground.ignoresSafeArea())
        // a tab coming back into view keeps its pages, so only the first appearance loads
        .task { await library.loadIfNeeded() }
        // back from the player, once its stop report has gone out, the cards show the new progress
        .onChange(of: connection.playbackEnded) {
            Task { await library.refresh() }
        }
    }
}

/// A poster grid card that opens its collection, or its movie's or series' details by TMDB ID: the check for a title biinge tracks or the series' state ring, NEW, progress, and the year or seasons with the rating
struct TVPosterCard: View {
    let connection: JellyfinConnection
    let item: BaseItemDto

    @Environment(\.tvOpen) private var open
    @Environment(MovieStore.self) private var movies
    @Environment(SeriesStore.self) private var series

    var body: some View {
        let isSeries = item.type == .series
        let state = DetailsTitle(item)?.state(movies: movies, series: series)
        // a series on a biinge list takes the check, and one Jellyfin finished shows no ring
        let showsRing = isSeries && state == nil && item.userData?.isPlayed != true && (item.userData?.playedPercentage ?? 0) > 0
        let percentage = item.userData?.playedPercentage ?? 0
        let isNew = item.dateCreated.map { $0 > Date.now.addingTimeInterval(-14 * 24 * 3600) } ?? false
        let seasons = item.childCount ?? 0
        let card = PosterImage(title: item.name ?? "", cornerRadius: 0, poster: connection.posterURL(item, maxWidth: 520),
                               frame: CGSize(width: 260, height: 390), titleFont: .system(size: 26), titlePadding: 20)
            .overlay(alignment: .topLeading) {
                if showsRing {
                    // the state ring: a white pie of the played share inside a white ring
                    Circle()
                        .fill(.black.opacity(0.55))
                        .overlay {
                            Circle()
                                .trim(from: 0, to: percentage / 100)
                                .stroke(Color(rgb: 0xF4F4F2), lineWidth: 18)
                                .rotationEffect(.degrees(-90))
                                .padding(9)
                        }
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(rgb: 0xF4F4F2), lineWidth: 3))
                        .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                        .frame(width: 36, height: 36)
                        .padding(14)
                } else if state != nil {
                    WatchedBadge()
                }
            }
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Text("NEW")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.72)
                        .foregroundStyle(Color.biingePrimary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 11)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                }
            }
            .overlay(alignment: .bottom) {
                if !isSeries && (item.userData?.playbackPositionTicks ?? 0) > 0 {
                    PlaybackBar(fraction: percentage / 100, height: 7, inset: 14)
                }
            }
        let style = TVCardButtonStyle(
            width: 260,
            height: 390,
            cornerRadius: 16,
            title: item.name ?? "",
            subtitle: isSeries ? (seasons == 1 ? "1 Season" : "\(seasons) Seasons") : item.productionYear.map(String.init) ?? "",
            rating: item.communityRating
        )
        switch item.type {
        case .boxSet:
            NavigationLink(value: TVRoute.collection(item)) { card }
                .buttonStyle(style)
        case .season, .episode:
            // a season or episode in a collection opens its series, whose TMDB ID only a fetch of the series tells
            Button {
                Task {
                    guard let service = connection.service else { return }
                    do {
                        if let title = try await DetailsTitle.resolve(item, service: service) { open(.title(title, poster: connection.posterURL(item, maxWidth: 880))) }
                    } catch {
                        // a failed fetch opens nothing, and a revoked token disconnects
                        _ = await connection.handleFailure(error)
                    }
                }
            } label: {
                card
            }
            .buttonStyle(style)
        default:
            // a title without a TMDB ID opens nothing
            NavigationLink(value: DetailsTitle(item).map { TVRoute.title($0, poster: connection.posterURL(item, maxWidth: 880)) }) { card }
                .buttonStyle(style)
        }
    }
}
