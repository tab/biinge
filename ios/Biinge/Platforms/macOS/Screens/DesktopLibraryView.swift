import JellyfinAPI
import SwiftUI

/// Movies or TV Shows: the title and count, the filter chips, the Genre and Sort menus over a paged poster grid
struct DesktopLibraryView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// Movies, otherwise TV Shows
    let isMovies: Bool

    @State private var sort = LibrarySort.recentlyAdded
    @State private var filter = LibraryFilter.all
    /// The genre the grid narrows to, nil for every genre
    @State private var genre: String?
    @State private var genres: PagedLibrary.Genres
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(connection: JellyfinConnection, apiClient: APIClient, isMovies: Bool) {
        self.connection = connection
        self.apiClient = apiClient
        self.isMovies = isMovies
        _genres = State(initialValue: PagedLibrary.Genres(connection: connection, type: isMovies ? .movie : .series))
    }

    var body: some View {
        let filters: [(LibraryFilter, String)] = [(.all, "All"), (.unwatched, "Unwatched"), (.watched, "Watched")]
        // TV shows offer no Runtime order
        let sorts: [(LibrarySort, String)] = [(.recentlyAdded, "Recently Added"), (.title, "Title"), (.releaseYear, "Release Year"), (.communityRating, "Community Rating")]
            + (isMovies ? [(.runtime, "Runtime")] : [])
        let title = isMovies ? "Movies" : "TV Shows"
        DesktopPagedGrid(
            connection: connection,
            list: isMovies ? .movies(sort, filter, genre: genre) : .series(sort, filter, genre: genre),
            minimumWidth: 160,
            empty: filter != .all || genre != nil
                ? (isMovies ? "No matching movies" : "No matching shows", "Nothing in your library matches this filter.")
                : isMovies
                ? ("No movies yet", "Add movies to your Jellyfin server’s Movies library.")
                : ("No shows yet", "Add shows to your Jellyfin server’s TV Shows library."),
            emptyAction: filter != .all || genre != nil ? ("Show All", {
                withAnimation(MotionCurve.standard.animation(MotionDuration.standard)) {
                    filter = .all
                    genre = nil
                }
            }) : nil,
            skeleton: PosterSkeleton(cornerRadius: 10, caption: 14)
        ) { _, total in
            // a new filter, genre or sort slides the pill fill in this transaction, and the grid itself cuts as the My Lists pills do
            let change = MotionCurve.standard.animation(MotionDuration.standard)
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(title)
                        .font(.system(size: 44, weight: .bold))
                        .tracking(-1.3)
                    if let total {
                        Text(isMovies ? (total == 1 ? "1 movie" : "\(total) movies") : (total == 1 ? "1 show" : "\(total) shows"))
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    HStack(spacing: 2) {
                        ForEach(filters, id: \.0) { option, label in
                            Button {
                                // the fill slides as the new grid cuts in (Reduce Motion crossfades the fill and the grid)
                                withAnimation(change) { filter = option }
                            } label: {
                                Text(label)
                                    .font(.system(size: 14, weight: .medium))
                                    .padding(.horizontal, 15)
                                    .frame(height: 32)
                                    .foregroundStyle(filter == option ? Color.biingeText : Color.biingeText.opacity(0.72))
                                    .background {
                                        if filter == option {
                                            Capsule()
                                                .fill(Color.biingeText.opacity(0.16))
                                                // one shared fill slides between the pills, while a fill of each pill's own crossfades
                                                .matchedGeometryEffect(id: reduceMotion ? AnyHashable(option) : AnyHashable("selection"), in: pill)
                                        }
                                    }
                                    .contentShape(Capsule())
                            }
                            .accessibilityAddTraits(filter == option ? .isSelected : [])
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(3)
                    .background(Color.biingeText.opacity(0.06), in: Capsule())
                    if !genres.names.isEmpty {
                        Menu {
                            Picker("Genre", selection: $genre.animation(change)) {
                                Text("All Genres").tag(String?.none)
                                ForEach(genres.names, id: \.self) { name in
                                    Text(name).tag(String?.some(name))
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            MenuLabel(title: genre ?? "All Genres", systemImage: "theatermasks")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    } else if genres.failed {
                        Menu {
                            Button("Retry") { Task { await genres.load() } }
                        } label: {
                            MenuLabel(title: "Genres unavailable", systemImage: "exclamationmark.triangle")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    Spacer()
                    Menu {
                        Picker("Sort by", selection: $sort.animation(change)) {
                            ForEach(sorts, id: \.0) { option, label in
                                Text(label).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        MenuLabel(title: sorts.first { $0.0 == sort }?.1 ?? "", systemImage: "arrow.up.arrow.down")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        } cell: { item in
            DesktopPosterCard(connection: connection, apiClient: apiClient, item: item)
        }
        // a new sort, filter or genre starts the grid again from its first page, whose opaque background covers the old grid at once, while the old grid's fade underneath carries the pill fill's slide (Reduce Motion crossfades them, and a transition outside the ids is ignored)
        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .identity, removal: .opacity))
        .id(sort)
        .id(filter)
        .id(genre)
        .navigationTitle(title)
        .task { await genres.load() }
    }
}

/// A header menu's label in the look of the filter pills beside it: the icon, the current choice and a small chevron in a capsule as tall as the pills' track
struct MenuLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
            Text(title)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.6)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.biingeText)
        .padding(.horizontal, 15)
        // the pills' 32 pt and their track's 3 pt inset on each side
        .frame(height: 38)
        .background(Color.biingeText.opacity(0.06), in: Capsule())
        .contentShape(Capsule())
    }
}

/// Continue Watching: a paged grid of progress cards, which open their details on a click
struct ContinueWatchingView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient

    @Environment(\.macOpen) private var open

    var body: some View {
        DesktopPagedGrid(
            connection: connection,
            list: .continueWatching,
            minimumWidth: 300,
            empty: ("Nothing in progress", "Movies and episodes you start watching on any device show up here.")
        ) { _, _ in
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Continue Watching")
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1.3)
                Text("Synced from Jellyfin across your devices")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        } cell: { item in
            DesktopContinueCard(connection: connection, item: item)
                .macCardActions {
                    Task {
                        guard let service = connection.service else { return }
                        do {
                            // the details show the Jellyfin poster (an episode's series poster) in place of the card's landscape art
                            if let title = try await DetailsTitle.resolve(item, service: service) {
                                open(.title(title, poster: connection.posterURL(item, maxWidth: 640)))
                            }
                        } catch {
                            // a failed fetch opens nothing, and a revoked token disconnects
                            _ = await connection.handleFailure(error)
                        }
                    }
                }
                .macItemMenu(item, connection: connection, apiClient: apiClient)
        }
        .navigationTitle("Continue Watching")
    }
}

/// Next Up: a paged grid of the next episode of each show in progress, in Home's Next Up look
struct NextUpView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient

    var body: some View {
        DesktopPagedGrid(
            connection: connection,
            list: .nextUp,
            minimumWidth: 420,
            empty: ("Nothing up next", "The next episode of each show you’re watching shows up here.")
        ) { _, _ in
            Text("Next Episodes")
                .font(.system(size: 44, weight: .bold))
                .tracking(-1.3)
        } cell: { item in
            NextUpCard(connection: connection, apiClient: apiClient, item: item)
        }
        .navigationTitle("Next Episodes")
    }
}

/// Recently Added: movies and series together, newest added first, as a paged poster grid
struct RecentlyAddedView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient

    var body: some View {
        DesktopPagedGrid(
            connection: connection,
            list: .recentlyAdded,
            minimumWidth: 160,
            empty: ("Your library is empty", "Add movies and shows to your Jellyfin server’s Movies and TV Shows libraries."),
            skeleton: PosterSkeleton(cornerRadius: 10, caption: 14)
        ) { _, total in
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Recently Added")
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1.3)
                if let total {
                    Text(total == 1 ? "1 title" : "\(total) titles")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
        } cell: { item in
            DesktopPosterCard(connection: connection, apiClient: apiClient, item: item)
        }
        .navigationTitle("Recently Added")
    }
}

/// A paged grid of one Jellyfin list under its header, with the loading, empty and offline states and a failed later page's Retry (the columns reflow with the window)
struct DesktopPagedGrid<Header: View, Cell: View>: View {
    let connection: JellyfinConnection
    /// The narrowest a column gets before the grid drops one
    let minimumWidth: CGFloat
    /// The empty state's title and guidance
    let empty: (title: String, text: String)
    /// The empty state's action in place of Retry (a filter's Show All)
    var emptyAction: (label: String, perform: () -> Void)?
    /// The card the first page's skeleton repeats, nil for a spinner (a grid whose cells aren't posters)
    var skeleton: PosterSkeleton?
    /// The header over the grid, given the loaded items and the list's total (nil until the first page lands)
    let header: ([BaseItemDto], Int?) -> Header
    let cell: (BaseItemDto) -> Cell

    @State private var library: PagedLibrary
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false

    init(
        connection: JellyfinConnection,
        list: LibraryList,
        minimumWidth: CGFloat,
        empty: (title: String, text: String),
        emptyAction: (label: String, perform: () -> Void)? = nil,
        skeleton: PosterSkeleton? = nil,
        @ViewBuilder header: @escaping ([BaseItemDto], Int?) -> Header,
        @ViewBuilder cell: @escaping (BaseItemDto) -> Cell
    ) {
        self.connection = connection
        self.minimumWidth = minimumWidth
        self.empty = empty
        self.emptyAction = emptyAction
        self.skeleton = skeleton
        self.header = header
        self.cell = cell
        _library = State(initialValue: PagedLibrary(connection: connection, list: list))
    }

    var body: some View {
        let items = library.shown
        let total = library.shownTotal
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(items, total)
                if !isSkeletonHeld, let total, total > 0 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 22)], alignment: .leading, spacing: 30) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            cell(item)
                                .environment(\.posterFadeIndex, index)
                                .onAppear {
                                    // scrolling to the last 20 loaded items loads the next page
                                    if index >= items.count - 20 { Task { await library.loadMore() } }
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    if let pageFailure = library.pageFailure {
                        HStack(spacing: 14) {
                            Label("Couldn’t load more. \(pageFailure.message)", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(rgb: 0xFF8A8D))
                            Button("Retry") {
                                Task {
                                    if pageFailure.isFirstPage {
                                        await library.load()
                                    } else {
                                        await library.loadMore()
                                    }
                                }
                            }
                            .disabled(library.isLoading)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if !isSkeletonHeld, total == 0 {
                    ContentUnavailableView {
                        Label(empty.title, systemImage: emptyAction == nil ? "film.stack" : "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(empty.text)
                    } actions: {
                        if let emptyAction {
                            Button(emptyAction.label, action: emptyAction.perform)
                        } else {
                            Button("Retry") { Task { await library.reload() } }
                        }
                    }
                    .padding(.vertical, 60)
                } else if !isSkeletonHeld, let failure = library.failure {
                    ContentUnavailableView {
                        Label("Can’t reach \(connection.serverURL?.host() ?? "the server")", systemImage: "icloud.slash")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Retry") { Task { await library.reload() } }
                    }
                    .padding(.vertical, 60)
                } else if let skeleton {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 22)], alignment: .leading, spacing: 30) {
                        ForEach(0..<12, id: \.self) { _ in
                            skeleton
                        }
                    }
                    .loadingSkeleton(isHeld: $isSkeletonHeld)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        // back from a pushed screen the grid keeps its pages, so only the first appearance loads
        .task { await library.loadIfNeeded() }
        // back from the player, once its stop report has gone out, the cards show the new progress
        .onChange(of: connection.playbackEnded) {
            Task { await library.refresh() }
        }
    }
}

/// A poster grid card filling its column that opens its collection, or its movie's or series' details by TMDB ID on a click: artwork with the check for a title biinge tracks, then the title, the year or seasons and the rating
struct DesktopPosterCard: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let item: BaseItemDto

    @Environment(\.macOpen) private var open

    var body: some View {
        let isSeries = item.type == .series
        let seasons = item.childCount ?? 0
        let card = VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        PosterImage(title: item.name ?? "", cornerRadius: 0, poster: connection.posterURL(item, maxWidth: 400), frame: proxy.size, titleFont: .system(size: 14), titlePadding: 12)
                    }
                }
                .trackedBadge(DetailsTitle(item))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.biingeText.opacity(0.07), lineWidth: 1))
                .posterHover(cornerRadius: 10)
                .macMorphSource(DetailsTitle(item), url: connection.posterURL(item, maxWidth: 400))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name ?? "")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 8) {
                    Text(isSeries ? (seasons == 1 ? "1 Season" : "\(seasons) Seasons") : item.productionYear.map(String.init) ?? "")
                    Spacer(minLength: 0)
                    if let rating = item.communityRating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.biingePrimary)
                            Text(rating, format: .number.precision(.fractionLength(1)))
                        }
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .contentShape(Rectangle())
        switch item.type {
        case .boxSet:
            // a collection tile gets no context menu
            NavigationLink(value: DesktopRoute.collection(item)) { card }
        case .season, .episode:
            // a season or episode in a collection opens its series, whose TMDB ID only a fetch of the series tells
            card
                .macCardActions {
                    Task {
                        guard let service = connection.service else { return }
                        do {
                            if let title = try await DetailsTitle.resolve(item, service: service) { open(.title(title, poster: connection.posterURL(item, maxWidth: 640))) }
                        } catch {
                            // a failed fetch opens nothing, and a revoked token disconnects
                            _ = await connection.handleFailure(error)
                        }
                    }
                }
                .macItemMenu(item, connection: connection, apiClient: apiClient)
        default:
            card
                .macCardActions {
                    // a title without a TMDB ID opens nothing
                    if let title = DetailsTitle(item) { open(.title(title, poster: connection.posterURL(item, maxWidth: 640))) }
                }
                .macItemMenu(item, connection: connection, apiClient: apiClient)
        }
    }
}
