import JellyfinAPI
import SwiftUI

/// The Library pill of Movies or TV: Continue Watching, Recently Added and the full Jellyfin grid with its sort, or the state that stands in for them
struct MobileLibraryView: View {
    let connection: JellyfinConnection
    /// Movies, otherwise TV Shows
    let isMovies: Bool
    /// Switches to Profile and opens its Jellyfin sheet (the not connected state's action)
    let connectInProfile: () -> Void

    @Environment(\.apiClient) private var apiClient
    @Environment(\.presentTitle) private var presentTitle
    @Environment(\.presentLibraryTitle) private var presentLibraryTitle
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sort = LibrarySort.recentlyAdded
    /// Set while the first load's shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    /// Set while a new sort's shown skeleton holds its 500 ms
    @State private var isSortSkeletonHeld = false
    /// The movies, or the episodes, Jellyfin's resume list holds
    @State private var resume: [BaseItemDto] = []
    @State private var recent: [BaseItemDto] = []
    /// The full grid, which pages in as it scrolls
    @State private var grid: PagedLibrary
    /// Bumped by Try Again, which loads the library again
    @State private var attempt = 0

    /// Each library's last rows by user and kind, kept in memory for the app's run so a return to the pill shows them at once
    @MainActor private static var rows: [String: Rows] = [:]

    init(connection: JellyfinConnection, isMovies: Bool, connectInProfile: @escaping () -> Void) {
        self.connection = connection
        self.isMovies = isMovies
        self.connectInProfile = connectInProfile
        // a library loaded on an earlier visit shows at once while its load refreshes it
        if let rows = Self.rows["\(connection.userID ?? "")-\(isMovies)"] {
            _resume = State(initialValue: rows.resume)
            _recent = State(initialValue: rows.recent)
        }
        let list: LibraryList = isMovies ? .movies(.recentlyAdded, .all) : .series(.recentlyAdded, .all)
        _grid = State(initialValue: PagedLibrary(connection: connection, list: list))
    }

    private var gridList: LibraryList {
        isMovies ? .movies(sort, .all) : .series(sort, .all)
    }

    var body: some View {
        let server = connection.serverName ?? "your server"
        Group {
            if let state = isSkeletonHeld ? .loading : LoadState(isConnected: connection.isConnected, total: grid.total, failure: grid.failure) {
                Group {
                    switch state {
                    case .loading:
                        ScrollView {
                            gridSkeleton(isHeld: $isSkeletonHeld)
                                .padding(.top, 8)
                        }
                        .scrollDisabled(true)
                    case .empty:
                        ContentUnavailableView {
                            Label(isMovies ? "No movies on \(server) yet" : "No shows on \(server) yet", systemImage: isMovies ? "film" : "tv")
                        } description: {
                            Text(isMovies
                                ? "Movies you add to the Movies library in Jellyfin show up here. Want and Watched still show your lists."
                                : "Shows you add to the TV Shows library in Jellyfin show up here. Want, Watching and Watched still show your lists.")
                        }
                    case .notConnected:
                        ContentUnavailableView {
                            Label("Connect Jellyfin to browse", systemImage: "link")
                        } description: {
                            Text("Sign in with your Jellyfin account in Profile to browse and play \(server) here. Your lists work without it.")
                        } actions: {
                            Button("Connect in Profile", systemImage: "person", action: connectInProfile)
                                .buttonStyle(.glassProminent)
                                .tint(Color.biingeText)
                                .foregroundStyle(Color.biingeBackground)
                        }
                    case .failed:
                        ContentUnavailableView {
                            Label("Can’t reach \(server)", systemImage: "icloud.slash")
                        } description: {
                            Text("The library and Play come back when the server does. Your lists and Search still work.")
                        } actions: {
                            Button("Try Again", systemImage: "arrow.clockwise") {
                                // an empty library shows the loading state again, not the empty one
                                grid.clear()
                                attempt += 1
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // the first page of a library not seen yet shifts in 20 pt (Reduce Motion crossfades it)
                library
                    .transition(.asymmetric(
                        insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 20)),
                        removal: .opacity
                    ).animation(MotionCurve.standard.animation(MotionDuration.standard)))
            }
        }
        // the tabs stay mounted across a disconnect, so one user's library never shows to the next
        .onChange(of: connection.userID) {
            grid.clear()
            resume = []
            recent = []
        }
        // a stopped play moves Continue Watching, and a new sort starts the grid again
        .task(id: "\(connection.userID ?? "")-\(connection.playbackEnded)-\(attempt)-\(sort)") { await load() }
    }

    private var library: some View {
        let sorts: [(LibrarySort, String)] = [(.title, "Title"), (.recentlyAdded, "Date Added"), (.releaseYear, "Year")]
        // Jellyfin may still report a title biinge just marked watched, and a failed mark brings its card back
        let resume = resume.filter { $0.id.map(connection.watchedIDs.contains) != true }
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !resume.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Continue Watching")
                            .font(.biingeSubhead)
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(Array(resume.enumerated()), id: \.element.id) { index, item in
                                    let source = "continue-\(item.id ?? "")"
                                    ContinueCard(connection: connection, item: item, source: source) {
                                        Task {
                                            guard let service = connection.service else { return }
                                            do {
                                                // the details show the Jellyfin poster (an episode's series poster) in place of the card's landscape art
                                                if let title = try await DetailsTitle.resolve(item, service: service) {
                                                    presentLibraryTitle(title, source, connection.posterURL(item, maxWidth: 720))
                                                }
                                            } catch {
                                                // a failed fetch opens nothing, and a revoked token disconnects
                                                _ = await connection.handleFailure(error)
                                            }
                                        }
                                    } play: {
                                        attemptPlay {
                                            guard let apiClient else { return }
                                            try await PlayResolution.play(item, fromStart: false, connection: connection, apiClient: apiClient) { presentTitle($0, nil) }
                                        }
                                    }
                                    .environment(\.posterFadeIndex, index)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recently Added")
                            .font(.biingeSubhead)
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 10) {
                                ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                                    // Recently Added repeats titles of the grid below, so each row names its own cells
                                    let source = "recent-\(item.id ?? "")"
                                    Button {
                                        // a title without a TMDB ID opens nothing
                                        if let title = DetailsTitle(item) { presentLibraryTitle(title, source, connection.posterURL(item, maxWidth: 720)) }
                                    } label: {
                                        LibraryPoster(connection: connection, item: item, cornerRadius: 9, showsNew: true)
                                            .frame(width: 100)
                                            .environment(\.posterFadeIndex, index)
                                    }
                                    .buttonStyle(.pressable)
                                    .detailTransitionSource(source)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(isMovies ? "All Movies" : "All TV Shows")
                                .font(.biingeSubhead)
                            if let total = grid.total {
                                Text("\(total)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.biingeTextSecondary)
                            }
                        }
                        Spacer()
                        Menu {
                            Picker("Sort by", selection: $sort) {
                                ForEach(sorts, id: \.0) { option, label in
                                    Text(label).tag(option)
                                }
                            }
                        } label: {
                            Label(sorts.first { $0.0 == sort }?.1 ?? "", systemImage: "arrow.up.arrow.down")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.biingeText.opacity(0.85))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Color.biingeFill(0.06), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.biingeFill(0.06)))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Sort by \(sorts.first { $0.0 == sort }?.1 ?? "")")
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, 16)
                    if grid.items.isEmpty || isSortSkeletonHeld {
                        // a new sort with no remembered page clears the grid until its first page lands
                        if grid.pageFailure == nil {
                            gridSkeleton(isHeld: $isSortSkeletonHeld)
                        }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(Array(grid.items.enumerated()), id: \.element.id) { index, item in
                                let source = "library-\(item.id ?? "")"
                                Button {
                                    // a title without a TMDB ID opens nothing
                                    if let title = DetailsTitle(item) { presentLibraryTitle(title, source, connection.posterURL(item, maxWidth: 720)) }
                                } label: {
                                    LibraryPoster(connection: connection, item: item, cornerRadius: 10, showsNew: false)
                                        .environment(\.posterFadeIndex, index)
                                }
                                .buttonStyle(.pressable)
                                .detailTransitionSource(source)
                                .onAppear {
                                    // scrolling to the last 20 loaded items loads the next page
                                    if index >= grid.items.count - 20 { Task { await grid.loadMore() } }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    if let pageFailure = grid.pageFailure {
                        ErrorBanner(message: "Couldn’t load the library. \(pageFailure.message)") {
                            Task {
                                if pageFailure.isFirstPage {
                                    await load()
                                } else {
                                    await grid.loadMore()
                                }
                            }
                        }
                        .disabled(grid.isLoading)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
        .onChange(of: sort) { grid.list = gridList }
    }

    /// The grid's loading skeleton, in its own three columns, holding `isHeld` once it shows
    private func gridSkeleton(isHeld: Binding<Bool>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(0..<12, id: \.self) { _ in
                PosterSkeleton(cornerRadius: 10)
            }
        }
        .padding(.horizontal, 16)
        .loadingSkeleton(isHeld: isHeld)
    }

    /// Loads Continue Watching and Recently Added together with the grid's first page, and keeps them only when the page lands (the grid shows the load's error)
    private func load() async {
        guard let service = connection.service else { return }
        var resumed: [BaseItemDto] = []
        var added: [BaseItemDto] = []
        let landed = await grid.load {
            async let resumePage = service.page(of: .continueWatching, startIndex: 0, limit: 40)
            async let recentPage = service.page(of: isMovies ? .recentlyAddedMovies : .recentlyAddedSeries, startIndex: 0, limit: 16)
            (resumed, added) = try await (resumePage.items, recentPage.items)
        }
        guard landed else { return }
        // shortcut: the resume list holds both kinds and is filtered here, so a long one can push this tab's items past the first 40
        resume = resumed.filter { $0.type == (isMovies ? .movie : .episode) }
        recent = added
        Self.rows["\(connection.userID ?? "")-\(isMovies)"] = Rows(resume: resume, recent: recent)
    }
}

/// Continue Watching and Recently Added as one load brought them
private struct Rows {
    let resume: [BaseItemDto]
    let recent: [BaseItemDto]
}

/// A Jellyfin poster: the 2:3 art with the check for a title biinge tracks, and NEW for an item added in the last 14 days when it shows one
private struct LibraryPoster: View {
    let connection: JellyfinConnection
    let item: BaseItemDto
    let cornerRadius: CGFloat
    let showsNew: Bool

    @Environment(MovieStore.self) private var movies
    @Environment(SeriesStore.self) private var series

    var body: some View {
        let state = DetailsTitle(item)?.state(movies: movies, series: series)
        let isNew = showsNew && (item.dateCreated.map { $0 > Date.now.addingTimeInterval(-14 * 24 * 3600) } ?? false)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.biingeSecondaryCard)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                CachedImage(url: connection.posterURL(item, maxWidth: 400), maxPixel: 400) {
                    Text(item.name ?? "")
                        .font(.biingeFootnote)
                        .foregroundStyle(Color.biingeGrayDark)
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if state != nil { WatchedBadge() }
            }
            .overlay(alignment: .topTrailing) {
                if isNew { NewBadge() }
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.biingeFill(0.07)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name ?? "")
            .accessibilityValue(state == .watched ? "Watched" : state != nil ? "In your library" : "")
    }
}

/// A Continue Watching card: landscape art with the time left and a progress bar under a Play button, then the title and the episode or year
struct ContinueCard: View {
    let connection: JellyfinConnection
    let item: BaseItemDto
    /// The ID the art marks as the source its details grow out of (the caller presents them from the same ID)
    let source: String
    let open: () -> Void
    let play: () -> Void

    var body: some View {
        let isEpisode = item.type == .episode
        let title = (isEpisode ? item.seriesName : item.name) ?? ""
        let left = (item.runTimeTicks ?? 0) - (item.userData?.playbackPositionTicks ?? 0)
        VStack(alignment: .leading, spacing: 7) {
            Button(action: open) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.biingeSurface)
                    .frame(width: 216, height: 122)
                    .overlay {
                        CachedImage(url: connection.landscapeURL(item, maxWidth: 600), maxPixel: 600) {
                            Text(title)
                                .font(.biingeFootnote)
                                .foregroundStyle(Color.biingeGrayDark)
                                .padding(8)
                        }
                    }
                    .overlay {
                        LinearGradient(
                            stops: [.init(color: .black.opacity(0), location: 0.45), .init(color: .black.opacity(0.75), location: 1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottom) {
                        PlaybackBar(fraction: (item.userData?.playedPercentage ?? 0) / 100)
                    }
                    .overlay(alignment: .bottomLeading) {
                        // the prototype's white text over the darkened art in either appearance
                        Text("\(duration(ticks: max(left, 0))) left")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.leading, 10)
                            .padding(.bottom, 20)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.biingeFill(0.07)))
            }
            .buttonStyle(.pressable)
            .detailTransitionSource(source)
            .accessibilityLabel(title)
            .overlay {
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Play \(title)")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(isEpisode ? "\(episodeCode(item)) · \(item.name ?? "")" : item.productionYear.map(String.init) ?? "")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.biingeTextSecondary)
            }
            .lineLimit(1)
            .frame(width: 216, alignment: .leading)
        }
    }
}
