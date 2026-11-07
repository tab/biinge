import JellyfinAPI
import SwiftUI

/// The Mac sidebar sections
enum DesktopSection: Hashable {
    case home, movies, series, collections, continueWatching, recentlyAdded, want, watching, watched, statistics, wantToPlay, playing, played

    var title: String {
        switch self {
        case .home: "Home"
        case .movies: "Movies"
        case .series: "TV Shows"
        case .collections: "Collections"
        case .continueWatching: "Continue Watching"
        case .recentlyAdded: "Recently Added"
        case .want: "Want to Watch"
        case .watching: "Watching"
        case .watched: "Watched"
        case .statistics: "Statistics"
        case .wantToPlay: "Want to Play"
        case .playing: "Playing"
        case .played: "Played"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .movies: "film"
        case .series: "tv"
        case .collections: "rectangle.stack"
        case .continueWatching: "play.circle"
        case .recentlyAdded: "clock"
        case .want: "bookmark"
        case .watching: "circle.lefthalf.filled"
        case .watched: "checkmark.circle"
        case .statistics: "chart.bar"
        case .wantToPlay: "bookmark"
        case .playing: "gamecontroller"
        case .played: "checkmark.circle"
        }
    }
}

/// A menu command the focused window performs
struct MenuAction: Equatable {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }

    // the writer's closure reads its state when it runs, so every action it makes does the same thing
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension FocusedValues {
    /// Pops the current section's navigation stack (nil when it has nothing to pop)
    @Entry var macGoBack: MenuAction?
    /// Opens the search overlay (nil while the player shows)
    @Entry var macSearch: MenuAction?
}

/// Pushes a screen onto the current section's navigation stack
struct DesktopOpenAction: Equatable {
    let perform: @MainActor (DesktopRoute) -> Void

    @MainActor func callAsFunction(_ route: DesktopRoute) {
        perform(route)
    }

    // the writer's closure reads its state when it runs, so every action it makes does the same thing
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// Pushes a screen onto the current section's navigation stack
    @Entry var macOpen = DesktopOpenAction { _ in }
    /// The section whose navigation stack shows this screen and that stack's depth (0 at its root), which a details screen's poster origin is saved under
    @Entry var macStack: (section: DesktopSection, depth: Int) = (.home, 0)
    /// Whether search or the player covers the navigation stack, which turns off the details' list menu shortcuts
    @Entry var macIsCovered = false
}

/// The Mac poster-to-details morph: the poster under the pointer, the artwork growing from it into the details poster once the details show, and back into it on Back
@MainActor @Observable final class PosterMorph {
    /// A poster's title, artwork and frame in the window
    struct Poster {
        let title: DetailsTitle
        let url: URL?
        let frame: CGRect
    }

    /// The poster last under the pointer (unobserved, as it changes with every hover)
    @ObservationIgnored var hovered: Poster?
    /// The poster under the pointer when a card was last clicked, which its details grow from
    @ObservationIgnored var clicked: Poster?
    /// The poster each open details screen grew from, by its section and depth, which Back returns the artwork to
    @ObservationIgnored var origins = StackOrigins<DesktopSection, Poster>()
    /// The poster the screen a section's stack last popped grew from, until the popped details read it, so a screen pushed over the details returns nothing
    @ObservationIgnored var popped: Poster?
    /// The poster the artwork grows from or returns to, nil when no morph runs
    var source: Poster?
    /// The details poster's frame the artwork grows into or returns from
    var target = CGRect.zero
    /// Whether the artwork heads back from the details into the poster they grew from
    var isReturning = false
    /// The frame of the source card the returning artwork lands on, nil until the card shows again
    var landing: CGRect?

    /// Starts the morph when the details of the clicked poster's title show their poster at this frame and this place in a section's stack (Reduce Motion cuts to the details)
    func arrive(_ title: DetailsTitle, at frame: CGRect, section: DesktopSection, depth: Int, reduceMotion: Bool) {
        // a details screen opened by the keyboard or from a card with no poster source finds no clicked poster of its title
        guard let clicked, clicked.title == title else { return }
        self.clicked = nil
        guard !reduceMotion else { return }
        origins.save(clicked, section: section, depth: depth)
        // a return still under way gives way to the new morph
        isReturning = false
        landing = nil
        target = frame
        source = clicked
    }

    /// Turns the artwork back from the details poster at this frame toward the poster they grew from, when a pop removed them (Reduce Motion cuts)
    func leave(_ title: DetailsTitle, from frame: CGRect, reduceMotion: Bool) {
        let origin = popped
        popped = nil
        guard let origin, !reduceMotion else {
            // a screen pushed over the details or a section switch drops a running entrance with them
            if source?.title == title, !isReturning { source = nil }
            return
        }
        // a running entrance turns around from wherever it has reached
        target = frame
        landing = nil
        source = origin
        isReturning = true
    }

    /// Lands the returning artwork on a card of its title at this frame over Morph, the one nearest where it was clicked when several show
    func land(at frame: CGRect) {
        guard isReturning, let source else { return }
        let origin = source.frame
        if let landing, hypot(landing.midX - origin.midX, landing.midY - origin.midY) <= hypot(frame.midX - origin.midX, frame.midY - origin.midY) { return }
        withAnimation(MotionCurve.standard.animation(MotionDuration.morph)) {
            landing = frame
        } completion: {
            // a later landing or a new morph took over
            guard self.isReturning, self.landing == frame else { return }
            self.source = nil
            self.isReturning = false
            self.landing = nil
        }
    }
}

/// The morph's artwork: it grows from the clicked poster into the details poster over Morph and fades out onto it over Quick, and on Back returns into the card or fades out where no card shows
private struct MorphOverlay: View {
    let morph: PosterMorph
    let source: PosterMorph.Poster
    /// The overlay's origin in the window, which the window frames are relative to
    let origin: CGPoint

    /// Whether the artwork has left the clicked poster, which a return starts from
    @State private var isGrown: Bool
    /// Set once a return starts, which fades the artwork out unless a card shows to land on
    @State private var isFading = false

    init(morph: PosterMorph, source: PosterMorph.Poster, origin: CGPoint) {
        self.morph = morph
        self.source = source
        self.origin = origin
        _isGrown = State(initialValue: morph.isReturning)
    }

    var body: some View {
        let frame = morph.landing ?? (isGrown ? morph.target : source.frame)
        // no larger than the card's decode, which the cache then serves, so the artwork shows at once
        CachedImage(url: source.url, maxPixel: max(source.frame.width, source.frame.height) * 2) { Color.biingeSecondaryCard }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: isGrown && morph.landing == nil ? 16 : 10))
            .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
            .opacity(isFading && morph.landing == nil ? 0 : 1)
            .onAppear {
                guard !morph.isReturning else { return }
                withAnimation(MotionCurve.standard.animation(MotionDuration.morph)) {
                    isGrown = true
                } completion: {
                    // a return, a later morph or leaving the details replaced this one
                    guard !morph.isReturning, morph.source?.frame == source.frame else { return }
                    withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { morph.source = nil }
                }
            }
            // the source card reports itself as the details pop, and a landing on it brings the artwork back before the fade shows
            .onChange(of: morph.isReturning, initial: true) { _, isReturning in
                guard isReturning else { return }
                withAnimation(MotionCurve.exit.animation(MotionDuration.quick)) {
                    isFading = true
                } completion: {
                    guard morph.isReturning, morph.landing == nil else { return }
                    morph.source = nil
                    morph.isReturning = false
                }
            }
    }
}

extension View {
    /// Marks this poster artwork as the one a click grows into its details and Back returns them to (nil for a card that opens no title)
    func macMorphSource(_ title: DetailsTitle?, url: URL?) -> some View {
        modifier(MorphSource(title: title, url: url))
    }

    /// Marks this details poster as the one the clicked poster grows into, hidden while the artwork grows over it
    func macMorphTarget(_ title: DetailsTitle) -> some View {
        modifier(MorphTarget(title: title))
    }

    /// Records the poster under the pointer as the clicked one when this card is clicked (apply it after the card's own taps, which an inner gesture would block)
    func macMorphClick() -> some View {
        modifier(MorphClick())
    }
}

private struct MorphClick: ViewModifier {
    @Environment(PosterMorph.self) private var morph: PosterMorph?

    func body(content: Content) -> some View {
        // a click records the poster under the pointer, which the details it opens grow from
        content.simultaneousGesture(TapGesture().onEnded { morph?.clicked = morph?.hovered })
    }
}

private struct MorphSource: ViewModifier {
    let title: DetailsTitle?
    let url: URL?

    @State private var isHovered = false
    @Environment(PosterMorph.self) private var morph: PosterMorph?

    func body(content: Content) -> some View {
        // the returning artwork stands in for every card of its title until it lands
        let isLanding = title != nil && morph?.isReturning == true && morph?.source?.title == title
        content
            .opacity(isLanding ? 0 : 1)
            .background {
                // only the poster under the pointer reports its frame, so a scrolling grid writes nothing
                if isHovered, let title {
                    Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        morph?.hovered = PosterMorph.Poster(title: title, url: url, frame: frame)
                    }
                }
            }
            .background {
                // a card of the returning title reports where it shows again, which the artwork lands on
                if isLanding {
                    Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { morph?.land(at: $0) }
                }
            }
            // the poster stays recorded after the pointer moves onto its caption, whose click grows it too (a click on another card finds another title)
            .onHover { isHovered = $0 }
    }
}

private struct MorphTarget: ViewModifier {
    let title: DetailsTitle

    /// The details poster's last frame, which Back returns the artwork from
    @State private var frame = CGRect.zero
    @Environment(PosterMorph.self) private var morph: PosterMorph?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.macStack) private var stack

    func body(content: Content) -> some View {
        content
            .opacity(morph?.source?.title == title ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                self.frame = frame
                morph?.arrive(title, at: frame, section: stack.section, depth: stack.depth, reduceMotion: reduceMotion)
            }
            // the details show again after the screen above them popped, so a later push over them isn't read as their pop
            .onAppear { morph?.popped = nil }
            .onDisappear { morph?.leave(title, from: frame, reduceMotion: reduceMotion) }
    }
}

/// The View menu's Back item, bound to ⌘[ and enabled while the current section has a screen to pop
struct BackCommands: Commands {
    @FocusedValue(\.macGoBack) private var goBack

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Back") { goBack?() }
                .keyboardShortcut("[")
                .disabled(goBack == nil)
        }
    }
}

/// The Edit menu's Search (⌘K) and Find (⌘F) items in place of the text Find items, enabled while the main window can open search
struct SearchCommands: Commands {
    @FocusedValue(\.macSearch) private var search

    var body: some Commands {
        CommandGroup(replacing: .textEditing) {
            Button("Search") { search?() }
                .keyboardShortcut("k")
                .disabled(search == nil)
            Button("Find") { search?() }
                .keyboardShortcut("f")
                .disabled(search == nil)
        }
    }
}

/// The sidebar's library card: Can’t reach your library with Retry while connected, Library not connected with Connect… after Not Now
private struct LibraryCard: View {
    let connection: JellyfinConnection

    /// Set while Retry's check runs, which swaps its label for a spinner
    @State private var isChecking = false
    @State private var isHovered = false

    var body: some View {
        let isConnected = connection.isConnected
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isConnected ? "icloud.slash" : "link")
                .font(.system(size: 16))
                .foregroundStyle(isConnected ? Color.biingeError : Color.biingeTextSecondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(isConnected ? "Can’t reach your library" : "Library not connected")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.biingeText.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    guard isConnected else {
                        // clearing Not Now brings back the connect screen
                        connection.skippedConnect = false
                        return
                    }
                    isChecking = true
                    Task {
                        await connection.checkReachability()
                        isChecking = false
                    }
                } label: {
                    // the label stays in the layout under the spinner, so the button keeps its size
                    ZStack {
                        Text(isConnected ? "Retry" : "Connect…")
                            .font(.system(size: 13, weight: .semibold))
                            .underline(isHovered)
                            .foregroundStyle(Color.biingeText)
                            .opacity(isChecking ? 0 : 1)
                        if isChecking {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isChecking)
                .onHover { isHovered = $0 }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

/// Mac shell: the Jellyfin connect screen until a connection exists or Not Now skips it, then the sidebar with a navigation stack per section
struct DesktopRootView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let authManager: AuthManager

    @State private var section: DesktopSection? = .home
    /// Each section keeps its own pushed screens while another section shows
    @State private var paths: [DesktopSection: NavigationPath] = [:]
    @State private var isSearching = false
    /// Bumped by each Search or Find shortcut, which puts the cursor back in an open search's field
    @State private var searchRequests = 0
    @State private var movieStore: MovieStore
    @State private var seriesStore: SeriesStore
    @State private var gameStore: GameStore
    @State private var morph = PosterMorph()
    /// The toast of a removal a context menu started, held here so it outlives the screen it came from
    @State private var toast: Toast?
    @Environment(\.openSettings) private var openSettings

    init(connection: JellyfinConnection, apiClient: APIClient, authManager: AuthManager) {
        self.connection = connection
        self.apiClient = apiClient
        self.authManager = authManager
        _movieStore = State(initialValue: MovieStore(apiClient: apiClient))
        _seriesStore = State(initialValue: SeriesStore(apiClient: apiClient))
        _gameStore = State(initialValue: GameStore(apiClient: apiClient))
    }

    var body: some View {
        Group {
            if connection.isConnected || connection.skippedConnect {
                splitView
            } else {
                DesktopConnectView(connection: connection, apiClient: apiClient, authManager: authManager)
            }
        }
        // a new connection opens on Home
        .onChange(of: connection.isConnected) { _, isConnected in
            guard isConnected else { return }
            section = .home
            paths = [:]
            morph.origins = StackOrigins()
            isSearching = false
        }
        .task(id: connection.isConnected) { await autoplay() }
        // a play Jellyfin reports as played marks the movie or episode watched in biinge too
        .onChange(of: connection.playbackEnded) {
            guard let item = connection.finishedPlay, let service = connection.service else { return }
            Task {
                // shortcut: a failed write goes unreported, as the player has closed; surface it if marks go missing in use
                guard let title = try? await DetailsTitle.resolve(item, service: service),
                      let mark = PlayedMark(item, title: title, isWatchedMovie: { movieStore.currentState(id: $0) == .watched }) else { return }
                try? await mark.write(apiClient: apiClient, movies: movieStore, series: seriesStore)
            }
        }
        // a Play whose lookup or item fetch failed says why and offers it again
        .playFailureAlert(connection: connection)
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Library") {
                    ForEach([DesktopSection.home, .movies, .series, .collections], id: \.self) { item in
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
                Section("Personal") {
                    ForEach([DesktopSection.continueWatching, .recentlyAdded, .statistics], id: \.self) { item in
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
                Section("My Lists") {
                    ForEach([DesktopSection.want, .watching, .watched], id: \.self) { item in
                        // movies have no Watching state
                        let count = switch item {
                        case .want: movieStore.wantMovies.count + seriesStore.wantSeries.count
                        case .watching: seriesStore.watchingSeries.count
                        default: movieStore.watchedMovies.count + seriesStore.watchedSeries.count
                        }
                        Label(item.title, systemImage: item.systemImage)
                            .badge(movieStore.hasLoaded && seriesStore.hasLoaded ? Text("\(count)") : nil)
                    }
                }
                Section("Games") {
                    ForEach([DesktopSection.wantToPlay, .playing, .played], id: \.self) { item in
                        let count = switch item {
                        case .wantToPlay: gameStore.wantGames.count
                        case .playing: gameStore.playingGames.count
                        default: gameStore.playedGames.count
                        }
                        Label(item.title, systemImage: item.systemImage)
                            .badge(gameStore.hasLoaded ? Text("\(count)") : nil)
                    }
                }
                Section("Global") {
                    // an action row without a tag, so it opens the overlay instead of becoming the selection
                    Button {
                        isSearching = true
                    } label: {
                        HStack {
                            Label("Search", systemImage: "magnifyingglass")
                            Spacer()
                            Text("⌘K").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // an action row too, as Settings opens its own window
                    Button {
                        openSettings()
                    } label: {
                        HStack {
                            Label("Settings", systemImage: "gearshape")
                            Spacer()
                            Text("⌘,").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            // the library card sits at the bottom of the sidebar: unreachable while connected, not connected after Not Now
            .safeAreaInset(edge: .bottom) {
                if connection.isConnected ? connection.isUnreachable : connection.skippedConnect {
                    LibraryCard(connection: connection)
                }
            }
        } detail: {
            if let section {
                NavigationStack(path: Binding { paths[section] ?? NavigationPath() } set: {
                    // a section switch tears the old stack down, which writes it an empty path that is no pop
                    guard self.section == section else { return }
                    // a pop returns the morph's artwork into the poster the popped details grew from in this section's stack
                    let depth = paths[section]?.count ?? 0
                    morph.popped = $0.count < depth ? morph.origins.pop(section: section, from: depth, to: $0.count) : nil
                    paths[section] = $0
                }) {
                    Group {
                        // the lists and statistics come from biinge, so they show with or without Jellyfin
                        if connection.isConnected || [.want, .watching, .watched, .statistics, .wantToPlay, .playing, .played].contains(section) {
                            switch section {
                            case .home:
                                DesktopHomeView(connection: connection, apiClient: apiClient)
                            case .movies:
                                DesktopLibraryView(connection: connection, apiClient: apiClient, isMovies: true)
                            case .series:
                                DesktopLibraryView(connection: connection, apiClient: apiClient, isMovies: false)
                            case .collections:
                                DesktopCollectionsView(connection: connection)
                            case .continueWatching:
                                ContinueWatchingView(connection: connection, apiClient: apiClient)
                            case .recentlyAdded:
                                RecentlyAddedView(connection: connection, apiClient: apiClient)
                            case .want, .watching, .watched:
                                DesktopListsView(section: section, connection: connection) { isSearching = true }
                            case .statistics:
                                DesktopStatisticsView(apiClient: apiClient)
                            case .wantToPlay, .playing, .played:
                                DesktopGamesView(section: section)
                            }
                        } else {
                            // the library sections read Jellyfin, so after Not Now they ask to connect instead
                            ContentUnavailableView {
                                Label("Connect Jellyfin to browse your library", systemImage: "link")
                            } description: {
                                Text("Your lists, search and title details come from Biinge and still work. Connect your Jellyfin account to browse and play what the server holds.")
                            } actions: {
                                // clearing Not Now brings back the connect screen
                                Button("Connect Jellyfin") { connection.skippedConnect = false }
                                Button("Open Want to Watch") { self.section = .want }
                            }
                            .navigationTitle(section.title)
                        }
                    }
                    .navigationDestination(for: DesktopRoute.self) { route in
                        switch route {
                        case .collection(let item):
                            DesktopCollectionView(connection: connection, apiClient: apiClient, collection: item)
                        case .title(.movie(let id), let poster):
                            DesktopMovieDetailsView(connection: connection, apiClient: apiClient, id: id, libraryPoster: poster)
                        case .title(.series(let id), let poster):
                            DesktopSeriesDetailsView(connection: connection, apiClient: apiClient, id: id, libraryPoster: poster)
                        case .game(let id):
                            DesktopGameDetailsView(apiClient: apiClient, id: id)
                        case .person(let id):
                            DesktopPersonDetailsView(apiClient: apiClient, id: id)
                        case .continueWatching:
                            ContinueWatchingView(connection: connection, apiClient: apiClient)
                        case .nextUp:
                            NextUpView(connection: connection, apiClient: apiClient)
                        case .recentlyAdded:
                            RecentlyAddedView(connection: connection, apiClient: apiClient)
                        case .collections:
                            DesktopCollectionsView(connection: connection)
                        }
                    }
                }
                // one stack per section, so a switch never animates one section's screens into another's
                .id(section)
                .toast($toast)
            }
        }
        .focusedSceneValue(\.macGoBack, backAction)
        // Escape pops like ⌘[, and closes the search, whose field takes Escape itself only while it has focus (the player overlay takes its own)
        .onExitCommand {
            if isSearching {
                isSearching = false
            } else {
                backAction?()
            }
        }
        // the shortcuts do nothing while the player covers the window
        .focusedSceneValue(\.macSearch, connection.playback == nil ? MenuAction {
            isSearching = true
            searchRequests += 1
        } : nil)
        // the player covers the whole window and the split view stays underneath, so the screen that started it keeps its state
        .toolbar(connection.playback == nil ? .automatic : .hidden, for: .windowToolbar)
        .overlay {
            // the artwork passes clicks through, so the details take input while it grows
            if let source = morph.source {
                GeometryReader { proxy in
                    MorphOverlay(morph: morph, source: source, origin: proxy.frame(in: .global).origin)
                }
                // a click on another title during a return starts a new artwork, which grows from its own poster
                .id(source.title)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay {
            // hidden under the player, so its Escape key equivalent never takes the player's Escape
            if isSearching, connection.playback == nil {
                DesktopSearchView(apiClient: apiClient, focusRequest: searchRequests) { route in
                    isSearching = false
                    // the picked result opens on the current section's stack
                    let target = section ?? .home
                    section = target
                    paths[target, default: NavigationPath()].append(route)
                } close: {
                    isSearching = false
                }
            }
            if let session = connection.playback {
                DesktopPlayerView(connection: connection, apiClient: apiClient, session: session)
            }
        }
        .environment(morph)
        // set out here because a NavigationStack keeps an environment set on it or inside it from the screens it pushes
        .environment(\.macOpen, DesktopOpenAction { route in paths[section ?? .home, default: NavigationPath()].append(route) })
        .environment(\.macStack, (section ?? .home, paths[section ?? .home]?.count ?? 0))
        .environment(\.macIsCovered, isSearching || connection.playback != nil)
        .environment(\.macToast, ToastAction { toast = $0 })
        // the lists and the details read the user's library from the stores, as on iPhone
        .environment(movieStore)
        .environment(seriesStore)
        .environment(gameStore)
        .task {
            async let movies: Void = movieStore.loadIfNeeded()
            async let series: Void = seriesStore.loadIfNeeded()
            async let games: Void = gameStore.loadIfNeeded()
            _ = await (movies, series, games)
        }
    }

    /// Pops the selected section's top screen, nil when the section shows its root
    private var backAction: MenuAction? {
        // the player and the search overlay cover the stack, so ⌘[ must not pop a screen nobody sees
        guard connection.playback == nil, !isSearching, let section, let path = paths[section], !path.isEmpty else { return nil }
        return MenuAction {
            // reads the section when it runs, as the menu keeps an earlier action after a switch to another section
            guard let section = self.section else { return }
            let depth = paths[section]?.count ?? 0
            morph.popped = morph.origins.pop(section: section, from: depth, to: depth - 1)
            paths[section]?.removeLast()
        }
    }

    /// Searches for JELLYFIN_AUTOPLAY and plays the first movie or episode once a connection exists, in Debug launches
    private func autoplay() async {
        #if DEBUG
        guard connection.isConnected, let term = ProcessInfo.processInfo.environment["JELLYFIN_AUTOPLAY"], let service = connection.service else { return }
        if let first = try? await service.search(term, types: [.movie, .episode], startIndex: 0, limit: 1).items.first {
            await connection.play(first)
        }
        #endif
    }
}
