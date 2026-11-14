import JellyfinAPI
import SwiftUI

/// Where focus sits on Home: the hero's first or second button, the failed reload's Retry, or a card by its row's title and its ID
enum HomeFocus: Hashable {
    case hero
    case heroSecond
    case retry
    case card(row: String, id: String)
}

/// Apple TV Home: the featured row, then rows of Jellyfin lists, with the empty library, offline and failed reload states
struct TVHomeView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// The selected top tab, which the Browse Your Library tiles switch
    @Binding var tab: TVTab

    /// The rows, with the recently added movies, then the recently added series, as the recently added lists
    @State private var feed: HomeFeed
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @State private var path: [TVRoute] = []
    /// The resolved item to play, through the resume sheet when it has a stored position
    @State private var playItem: BaseItemDto?
    /// The featured page on screen and its 9 s clock
    @State private var rotation = HeroRotation()
    @FocusState private var focus: HomeFocus?
    @Environment(\.attemptPlay) private var attemptPlay

    init(connection: JellyfinConnection, apiClient: APIClient, tab: Binding<TVTab>) {
        self.connection = connection
        self.apiClient = apiClient
        _tab = tab
        _feed = State(initialValue: HomeFeed(connection: connection, recentlyAdded: [(.recentlyAddedMovies, 9), (.recentlyAddedSeries, 20)]))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !isSkeletonHeld, let rows = feed.rows {
                    let heroes = feed.heroes
                    if heroes.isEmpty && rows.nextUp.isEmpty && rows.collections.isEmpty {
                        message(
                            icon: "film.stack",
                            title: "Your library is empty",
                            text: "Add movies and shows to your Jellyfin server’s Movies and TV Shows libraries.",
                            action: "Retry"
                        )
                    } else {
                        page(rows, heroes: heroes)
                    }
                } else if !isSkeletonHeld, let failure = feed.failure {
                    message(
                        icon: "icloud.slash",
                        title: "Can’t reach \(connection.serverURL?.host() ?? "the server")",
                        text: failure,
                        action: "Try Again"
                    )
                } else {
                    TVHomeSkeleton(isHeld: $isSkeletonHeld)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color.biingeText)
            .background { background }
            .tvRouteDestinations(connection: connection, apiClient: apiClient)
        }
        // Home keeps its own stack, so a card that resolves its details first pushes here
        .environment(\.tvOpen, TVOpenAction { route in path.append(route) })
        .tvPlayChoice($playItem, connection: connection) { path.append($0) }
        .task { await feed.load() }
        // back from the player, once its stop report has gone out, the rows show the new positions
        .onChange(of: connection.playbackEnded) {
            Task { await feed.load() }
        }
        // a Watched mark hides its title at once, then the reload resolves the details of a hero it promoted
        .onChange(of: connection.watchedIDs) {
            Task { await feed.hideWatched() }
        }
        // the first load lands focus on the hero's first button, or the first card when there's no hero
        .onChange(of: feed.rows != nil) { _, isLoaded in
            guard isLoaded, let rows = feed.rows else { return }
            // every featured page has a Play or a Details button from the start
            if !feed.heroes.isEmpty {
                focus = .hero
            } else if let id = rows.nextUp.first?.id {
                focus = .card(row: "Next Episodes", id: id)
            } else if let id = rows.collections.first?.id {
                focus = .card(row: "Collections", id: id)
            }
        }
    }

    /// Whether focus is on a row past Continue Watching, where the hero backdrop dims
    private var isPastFirstRow: Bool {
        if case .card(let row, _) = focus { return row != "Continue Watching" }
        return false
    }

    /// The featured page's landscape art blurred and dimmed behind the page, or the plain background without a hero
    private var background: some View {
        ZStack {
            Color.biingeBackground
            // the backdrop arrives with the page, after a shown skeleton's hold
            if !isSkeletonHeld, feed.rows != nil {
                let heroes = feed.heroes
                if let hero = heroes.isEmpty ? nil : heroes[min(rotation.index, heroes.count - 1)] {
                    ZStack {
                        TVBackdropArt(url: connection.landscapeURL(hero.item, maxWidth: 640))
                            // a new id fades the page's art in over the old under the rotation's animation (the default transition)
                            .id(hero.item.id)
                        LinearGradient(
                            stops: [.init(color: Color.biingeBackground.opacity(0.75), location: 0), .init(color: Color.biingeBackground.opacity(0.1), location: 0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        LinearGradient(
                            stops: [.init(color: Color.biingeBackground.opacity(0), location: 0.4), .init(color: Color.biingeBackground, location: 0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .opacity(isPastFirstRow ? 0.25 : 1)
                    .animation(MotionCurve.standard.animation(MotionDuration.emphasis), value: isPastFirstRow)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func page(_ rows: HomeFeed.Rows, heroes: [HomeHero]) -> some View {
        // the feed loads the recently added movies, then the recently added series
        let movies = rows.recentlyAdded[0]
        let series = rows.recentlyAdded[1]
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !heroes.isEmpty {
                    heroView(heroes, index: min(rotation.index, heroes.count - 1))
                } else {
                    // the tab bar keeps the first row clear
                    Spacer().frame(height: 170)
                }
                VStack(alignment: .leading, spacing: 72) {
                    // a failed reload keeps the rows an earlier load brought
                    if let reloadFailure = feed.reloadFailure {
                        HStack(spacing: 32) {
                            Label("Couldn’t refresh Home. \(reloadFailure)", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 29))
                                .foregroundStyle(Color(rgb: 0xFF8A8D))
                            Button {
                                Task { await feed.load() }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(PillButtonStyle())
                            .focused($focus, equals: .retry)
                        }
                        .padding(.horizontal, 96)
                        .focusSection()
                    }
                    HomeRow(title: "Continue Watching", items: rows.continueWatching, width: 520, height: 292, spacing: 48, focus: $focus, caption: { item in
                        item.type == .episode
                            ? (item.seriesName ?? "", "\(episodeCode(item)) · \(item.name ?? "")")
                            : (item.name ?? "", "Movie · \(item.productionYear.map(String.init) ?? "")")
                    }, select: { play($0) }, art: { item in
                        let title = item.type == .episode ? item.seriesName ?? "" : item.name ?? ""
                        PosterImage(title: title, cornerRadius: 0, poster: connection.landscapeURL(item, maxWidth: 1040),
                                    frame: CGSize(width: 520, height: 292), titleFont: .system(size: 26), titlePadding: 20)
                            .overlay {
                                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.5), .init(color: .black.opacity(0.75), location: 1)], startPoint: .top, endPoint: .bottom)
                            }
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("\(duration(ticks: (item.runTimeTicks ?? 0) - (item.userData?.playbackPositionTicks ?? 0))) left")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(Color(rgb: 0xF4F4F2))
                                        .padding(.bottom, 9)
                                    PlaybackBar(fraction: (item.userData?.playedPercentage ?? 0) / 100, height: 7, inset: 0)
                                }
                                .padding(.horizontal, 22)
                                .padding(.bottom, 18)
                            }
                    })
                    HomeRow(title: "Next Episodes", items: rows.nextUp, width: 440, height: 248, spacing: 44, focus: $focus, caption: { item in
                        (item.seriesName ?? "", "\(item.name ?? "") · \(duration(ticks: item.runTimeTicks ?? 0))")
                    }, select: { play($0) }, art: { item in
                        PosterImage(title: item.seriesName ?? "", cornerRadius: 0, poster: connection.landscapeURL(item, maxWidth: 880),
                                    frame: CGSize(width: 440, height: 248), titleFont: .system(size: 26), titlePadding: 20)
                            .overlay(alignment: .topLeading) {
                                Text(episodeCode(item))
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color(rgb: 0xF4F4F2))
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 12)
                                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                                    .padding(16)
                            }
                    })
                    HomeRow(title: "Recently Added Movies", items: movies.items, width: 260, height: 390, spacing: 48, cornerRadius: 16, focus: $focus, caption: { item in
                        (item.name ?? "", item.productionYear.map(String.init) ?? "")
                    }, select: { item in
                        // a title without a TMDB ID opens nothing
                        if let title = DetailsTitle(item) { path.append(.title(title, poster: connection.posterURL(item, maxWidth: 880))) }
                    }, art: { item in
                        PosterImage(title: item.name ?? "", cornerRadius: 0, poster: connection.posterURL(item, maxWidth: 520),
                                    frame: CGSize(width: 260, height: 390), titleFont: .system(size: 26), titlePadding: 20)
                            .trackedBadge(DetailsTitle(item))
                    })
                    HomeRow(title: "Recently Added TV Shows", items: series.items, width: 260, height: 390, spacing: 48, cornerRadius: 16, focus: $focus, caption: { item in
                        (item.name ?? "", item.childCount == 1 ? "1 Season" : "\(item.childCount ?? 0) Seasons")
                    }, select: { item in
                        // a title without a TMDB ID opens nothing
                        if let title = DetailsTitle(item) { path.append(.title(title, poster: connection.posterURL(item, maxWidth: 880))) }
                    }, art: { item in
                        PosterImage(title: item.name ?? "", cornerRadius: 0, poster: connection.posterURL(item, maxWidth: 520),
                                    frame: CGSize(width: 260, height: 390), titleFont: .system(size: 26), titlePadding: 20)
                            .trackedBadge(DetailsTitle(item))
                    })
                    // a focused 640-point tile grows 45 points a side, so the gap leaves 19 points to its neighbour
                    HomeRow(title: "Collections", items: rows.collections, width: 640, height: 360, spacing: 64, focus: $focus, caption: { _ in nil }, select: {
                        path.append(.collection($0))
                    }, art: { item in
                        TVCollectionTile(connection: connection, collection: item, width: 640, height: 360)
                    })
                    BrowseRow(connection: connection, movies: movies, series: series, tab: $tab, focus: $focus)
                }
            }
            .padding(.bottom, 72)
        }
        .ignoresSafeArea()
    }

    /// The featured page at the index with the page dots under the poster; left on the first button and right on the last turn the page, and it turns itself every 9 s with a crossfade while focus is on it or the tab bar
    private func heroView(_ heroes: [HomeHero], index: Int) -> some View {
        let hero = heroes[index]
        let item = hero.item
        let isEpisode = item.type == .episode
        let title = (isEpisode ? item.seriesName : item.name) ?? ""
        let kind = item.type == .movie ? "Movie" : "TV Show"
        let genres = item.genres?.prefix(3).joined(separator: ", ") ?? ""
        let meta: [String] = switch item.type {
        case .episode: [episodeCode(item), item.name ?? ""]
        case .series: [item.productionYear.map(String.init) ?? "", item.childCount == 1 ? "1 Season" : "\(item.childCount ?? 0) Seasons", genres]
        default: [item.productionYear.map(String.init) ?? "", duration(ticks: item.runTimeTicks ?? 0), genres]
        }
        let (playable, route) = heroButtons(item)
        let canResume = (playable?.userData?.playbackPositionTicks ?? 0) > 0
        // the button a right press turns the page from
        let last: HomeFocus = playable != nil && route != nil ? .heroSecond : .hero
        return ZStack(alignment: .topLeading) {
            PosterImage(title: title, cornerRadius: 0, poster: connection.posterURL(item, maxWidth: 800), frame: CGSize(width: 400, height: 600), titleFont: .system(size: 26), titlePadding: 20)
                // no watched check, which would scale with the poster's push-in
                .modifier(HeroPush())
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.biingeText.opacity(0.1), lineWidth: 1))
                .shadow(color: Color.biingeShadow.opacity(0.6), radius: 45, y: 40)
                .padding(.top, 150)
                .padding(.trailing, 120)
                .frame(maxWidth: .infinity, alignment: .trailing)
                // a new id fades the page's poster in over the old under the rotation's animation (the default transition)
                .id(item.id)
            if heroes.count > 1 {
                HStack(spacing: 10) {
                    ForEach(heroes.indices, id: \.self) { page in
                        Capsule()
                            .fill(Color.biingeText.opacity(page == index ? 1 : 0.35))
                            .frame(width: page == index ? 34 : 10, height: 10)
                    }
                }
                .frame(width: 400)
                .padding(.top, 780)
                .padding(.trailing, 120)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Featured title \(index + 1) of \(heroes.count)")
            }
            VStack(alignment: .leading, spacing: 26) {
                // the stack lays the leaving and the arriving page's text over each other while they cross
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 26) {
                        Text("\(hero.isResume ? "Continue Watching" : "Recently added") · \(kind)")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.biingeText.opacity(0.75))
                        Text(title)
                            .font(.system(size: title.count > 14 ? 104 : 128, weight: .bold))
                            .tracking((title.count > 14 ? 104 : 128) * -0.035)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                        HStack(spacing: 22) {
                            Text(meta.filter { !$0.isEmpty }.joined(separator: " · "))
                                .foregroundStyle(Color.biingeText.opacity(0.82))
                            if let rating = item.communityRating {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(Color.biingePrimary)
                                    Text(rating, format: .number.precision(.fractionLength(1)))
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .font(.system(size: 29))
                        Text(item.overview ?? "")
                            .font(.system(size: 30))
                            .lineSpacing(7)
                            .lineLimit(2)
                            .foregroundStyle(Color.biingeText.opacity(0.82))
                            .frame(maxWidth: 940, alignment: .leading)
                    }
                    // a new id fades the page's text in over the old under the rotation's animation (the default transition)
                    .id(item.id)
                }
                HStack(spacing: 22) {
                    if let playable {
                        Button { play(playable) } label: {
                            Label(canResume ? "Resume" : "Play", systemImage: "play.fill")
                        }
                        .focused($focus, equals: .hero)
                        if let route {
                            Button { path.append(route) } label: {
                                Label("Details", systemImage: "info.circle.fill")
                            }
                            .focused($focus, equals: .heroSecond)
                        }
                    } else if let route {
                        Button { path.append(route) } label: {
                            Label("Details", systemImage: "info.circle.fill")
                        }
                        .focused($focus, equals: .hero)
                    }
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 12)
                // nothing is focusable beside the buttons, so the presses past them turn the featured page
                .onMoveCommand { direction in
                    guard heroes.count > 1 else { return }
                    switch direction {
                    case .left where focus == .hero:
                        rotation.turn(to: (index + heroes.count - 1) % heroes.count, at: .now)
                    case .right where focus == last:
                        rotation.turn(to: (index + 1) % heroes.count, at: .now)
                    default:
                        return
                    }
                    focus = .hero
                }
            }
            .frame(width: 1100, alignment: .leading)
            .padding(.leading, 96)
            .padding(.top, 250)
        }
        .frame(maxWidth: .infinity, minHeight: 860, maxHeight: 860, alignment: .topLeading)
        .focusSection()
        .modifier(TVHeroRotation(rotation: $rotation, ids: heroes.map { $0.item.id ?? "" }, isPlaying: connection.playback != nil, focus: $focus) { heroButtons(heroes[$0].item) })
    }

    /// Resolves a card's or the hero's item by the one-match rule, then plays it through the resume sheet or opens the details it resolves to
    private func play(_ item: BaseItemDto) {
        attemptPlay {
            guard let service = connection.service else { return }
            switch try await PlayResolution.resolve(item, service: service, apiClient: apiClient) {
            case .play(let resolved): playItem = resolved
            case .details(let title): path.append(.title(title))
            case .nothing: break
            }
        }
    }

    /// The message state with an action that loads again
    private func message(icon: String, title: String, text: String, action: String) -> some View {
        Message(icon: icon, title: title, text: text, action: action) {
            Task { await feed.reload() }
        }
    }
}

/// Message state in the setup error screen's look: an icon, a title, the text and one or two actions
struct Message: View {
    let icon: String
    let title: String
    let text: String
    let action: String
    var actionIcon = "arrow.clockwise"
    /// The action beside the first one, nil for none
    var secondAction: (title: String, icon: String, perform: () -> Void)?
    let perform: () -> Void

    var body: some View {
        VStack(spacing: 40) {
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
            HStack(spacing: 32) {
                Button(action: perform) {
                    Label(action, systemImage: actionIcon)
                }
                if let secondAction {
                    Button(action: secondAction.perform) {
                        Label(secondAction.title, systemImage: secondAction.icon)
                    }
                }
            }
            .buttonStyle(PillButtonStyle())
        }
        .multilineTextAlignment(.center)
    }
}

extension TVHomeView {
    /// A featured item's Play item and Details route (a series plays its next up episode and offers Details only without one, and an episode opens its series' details once their fetch lands)
    private func heroButtons(_ item: BaseItemDto) -> (playable: BaseItemDto?, route: TVRoute?) {
        let route = (DetailsTitle(item) ?? item.id.flatMap { feed.heroTitles[$0] }).map { TVRoute.title($0, poster: connection.posterURL(item, maxWidth: 880)) }
        return (item.type == .series ? item.id.flatMap { feed.heroNextUps[$0] } : item, route)
    }
}

/// A titled Home row of cards that scrolls sideways with focus and brightens its title while one of its cards has focus
private struct HomeRow<Art: View>: View {
    let title: String
    let items: [BaseItemDto]
    let width: CGFloat
    let height: CGFloat
    let spacing: CGFloat
    var cornerRadius: CGFloat = 20
    let focus: FocusState<HomeFocus?>.Binding
    /// The title and subtitle under a card, nil for a tile that carries its own text
    let caption: (BaseItemDto) -> (title: String, subtitle: String)?
    let select: (BaseItemDto) -> Void
    @ViewBuilder let art: (BaseItemDto) -> Art

    private var holdsFocus: Bool {
        if case .card(let row, _) = focus.wrappedValue { return row == title }
        return false
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 28) {
                Text(title)
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(holdsFocus ? Color.biingeTextFocused : Color.biingeText.opacity(0.7))
                    .padding(.leading, 96)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let caption = caption(item)
                            Button { select(item) } label: {
                                art(item).frame(width: width, height: height)
                            }
                            .buttonStyle(TVCardButtonStyle(width: width, height: height, cornerRadius: cornerRadius, title: caption?.title, subtitle: caption?.subtitle))
                            .focused(focus, equals: .card(row: title, id: item.id ?? ""))
                            .environment(\.posterFadeIndex, index)
                        }
                    }
                    .padding(.horizontal, 96)
                }
                .scrollClipDisabled()
            }
            .focusSection()
        }
    }
}

/// The Browse Your Library row: a wide fanned tile per library that has items, which switches to its tab
private struct BrowseRow: View {
    let connection: JellyfinConnection
    let movies: LibraryPage
    let series: LibraryPage
    @Binding var tab: TVTab
    let focus: FocusState<HomeFocus?>.Binding

    private var holdsFocus: Bool {
        if case .card(let row, _) = focus.wrappedValue { return row == "Browse Your Library" }
        return false
    }

    var body: some View {
        if movies.total > 0 || series.total > 0 {
            VStack(alignment: .leading, spacing: 28) {
                Text("Browse Your Library")
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(holdsFocus ? Color.biingeTextFocused : Color.biingeText.opacity(0.7))
                    .padding(.leading, 96)
                // a focused tile grows 58 points a side, so the 80-point gap leaves 22 points to its neighbour, and two 824-point tiles still fill the 1920-point row
                HStack(spacing: 80) {
                    if movies.total > 0 {
                        tile(.movies, name: "Movies", count: "\(movies.total) movies", page: movies)
                    }
                    if series.total > 0 {
                        tile(.series, name: "TV Shows", count: "\(series.total) shows", page: series)
                    }
                }
                .padding(.horizontal, 96)
            }
            .focusSection()
        }
    }

    private func tile(_ target: TVTab, name: String, count: String, page: LibraryPage) -> some View {
        Button { tab = target } label: {
            FanTile(name: name, count: count, nameSize: 64, width: 824, height: 300, posters: page.items.prefix(3).map { connection.posterURL($0, maxWidth: 316) })
        }
        .buttonStyle(TVCardButtonStyle(width: 824, height: 300, cornerRadius: 20, title: nil, subtitle: nil))
        .focused(focus, equals: .card(row: "Browse Your Library", id: name))
    }
}

/// A collection tile: the collection's own poster, or a fan of its first three items' posters when it has none
struct TVCollectionTile: View {
    let connection: JellyfinConnection
    let collection: BaseItemDto
    let width: CGFloat
    let height: CGFloat

    @State private var items: [BaseItemDto] = []

    var body: some View {
        let own = collection.imageTags?[ImageType.primary.rawValue]
        let posters = own != nil ? [connection.posterURL(collection, maxWidth: 316)] : items.map { connection.posterURL($0, maxWidth: 316) }
        let count = collection.childCount ?? 0
        FanTile(name: collection.name ?? "", count: count == 1 ? "1 title" : "\(count) titles", nameSize: 44, width: width, height: height, posters: posters)
            .task {
                // three poster loads per tile only when the collection has no poster of its own
                guard own == nil, let service = connection.service, let id = collection.id else { return }
                items = (try? await service.page(of: .collection(id), startIndex: 0, limit: 3).items) ?? []
            }
    }
}

/// A wide tile over its blurred centre poster, with up to three fanned posters and the name and count in the corner
private struct FanTile: View {
    let name: String
    let count: String
    let nameSize: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// The mockup's order: the second poster sits in the centre, the first on the left and the third (or the first) on the right
    let posters: [URL?]

    var body: some View {
        let center = posters.count > 1 ? posters[1] : posters.isEmpty ? nil : posters[0]
        let left = posters.count > 1 ? posters[0] : nil
        let right = posters.count > 2 ? posters[2] : left
        // the tile is art with light text over it, so it stays dark on any appearance
        ZStack(alignment: .topTrailing) {
            Color(rgb: 0x282828)
            CachedImage(url: center, maxPixel: 320) { Color.clear }
                .frame(width: width + 160, height: height + 160)
                .blur(radius: 46)
                .saturation(1.4)
                .colorMultiply(Color(white: 0.5))
                .frame(width: width, height: height)
            if let left {
                poster(left, width: 150, height: 225)
                    .rotationEffect(.degrees(-9))
                    .shadow(color: .black.opacity(0.5), radius: 17, y: 14)
                    .padding(.top, 44)
                    .padding(.trailing, 196)
            }
            if let right {
                poster(right, width: 150, height: 225)
                    .rotationEffect(.degrees(9))
                    .shadow(color: .black.opacity(0.5), radius: 17, y: 14)
                    .padding(.top, 44)
                    .padding(.trailing, 30)
            }
            if let center {
                poster(center, width: 158, height: 237)
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 18)
                    .padding(.top, 30)
                    .padding(.trailing, 112)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(size: nameSize, weight: .bold))
                    .tracking(nameSize * -0.025)
                Text(count)
                    .font(.system(size: 25))
                    .opacity(0.75)
            }
            .foregroundStyle(Color(rgb: 0xF4F4F2))
            .padding(.leading, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: width, height: height)
    }

    private func poster(_ url: URL, width: CGFloat, height: CGFloat) -> some View {
        CachedImage(url: url, maxPixel: height * 2) { Color(rgb: 0x282828) }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// An Apple TV card: the artwork lifts and catches a glare while focused, and the caption below brightens and moves clear of it (Reduce Motion: no scale, a 3 pt ring)
struct TVCardButtonStyle: ButtonStyle {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let title: String?
    let subtitle: String?
    /// The community rating at the subtitle's end, nil for none
    var rating: Float?

    func makeBody(configuration: Configuration) -> some View {
        Card(label: configuration.label, width: width, height: height, cornerRadius: cornerRadius, title: title, subtitle: subtitle, rating: rating)
    }

    /// Reads focus from the environment, which a ButtonStyle itself can't see
    private struct Card: View {
        let label: ButtonStyleConfiguration.Label
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
        let title: String?
        let subtitle: String?
        let rating: Float?

        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let isLifted = isFocused && !reduceMotion
            VStack(alignment: .leading, spacing: 22) {
                label
                    .overlay {
                        LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .white.opacity(0), location: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .opacity(isLifted ? 1 : 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    // Reduce Motion marks focus with a full-strength 3 pt ring in place of the lift
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.biingeText.opacity(isFocused && reduceMotion ? 1 : 0.06), lineWidth: isFocused && reduceMotion ? 3 : 1))
                    .shadow(color: Color.biingeShadow.opacity(isLifted ? 0.65 : 0.3), radius: isLifted ? 35 : 12, y: isLifted ? 36 : 10)
                    .scaleEffect(isLifted ? 1.14 : 1)
                    .offset(y: isLifted ? -4 : 0)
                if let title {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 29, weight: .semibold))
                            .foregroundStyle(isFocused ? Color.biingeTextFocused : Color.biingeText.opacity(0.78))
                        HStack(spacing: 12) {
                            Text(subtitle ?? "")
                            Spacer(minLength: 0)
                            if let rating {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(Color.biingePrimary)
                                    Text(rating, format: .number.precision(.fractionLength(1)))
                                }
                            }
                        }
                        .font(.system(size: 25))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                    }
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
                    // the scaled artwork grows by half of 14% downwards, so the caption steps clear of it
                    .offset(y: isLifted ? (height * 0.07).rounded() + 6 : 0)
                }
            }
            // a new focus retargets the running animation from where it is
            .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
        }
    }
}

/// Turns Home's featured page every 9 s of running time with the Ambient crossfade, and holds its time while a row below has focus, Home is off screen, the player is open or the app isn't active
private struct TVHeroRotation: ViewModifier {
    @Binding var rotation: HeroRotation
    /// The featured row's item IDs
    let ids: [String]
    /// Whether the player is open over Home
    let isPlaying: Bool
    let focus: FocusState<HomeFocus?>.Binding
    /// The Play item and Details route of the featured page at an index
    let buttons: (Int) -> (playable: BaseItemDto?, route: TVRoute?)

    /// Whether the featured row is on screen, as a pushed screen or another tab holds the rotation
    @State private var isShown = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let isFocusBelow = switch focus.wrappedValue {
        case .card, .retry: true
        default: false
        }
        let rotates = ids.count > 1 && isShown && scenePhase == .active && !isPlaying && !isFocusBelow
        content
            .onAppear { isShown = true }
            .onDisappear {
                isShown = false
                // a reload that empties the featured row removes this modifier before the change below can pause it
                rotation.pause(at: .now)
            }
            .onChange(of: rotates) {
                if rotates { rotation.resume(at: .now) } else { rotation.pause(at: .now) }
            }
            // a pause (the empty ID), a resume, every turn and a reload that changes the row restart the wait with the current row
            .task(id: rotates ? [String(rotation.index)] + ids : []) {
                guard rotates else { return }
                // the wait runs to what is left of the page's 9 s, which a pause moved later
                while (try? await Task.sleep(for: .seconds(max(0, HeroRotation.interval - rotation.elapsed(at: .now))))) != nil {
                    guard withAnimation(MotionCurve.standard.animation(MotionDuration.ambient), { rotation.advance(count: ids.count, at: .now) }) else { continue }
                    // focus stays on Details when the new page has both buttons, and otherwise lands on its first
                    if focus.wrappedValue == .hero || focus.wrappedValue == .heroSecond {
                        let next = buttons(rotation.index)
                        focus.wrappedValue = focus.wrappedValue == .heroSecond && next.playable != nil && next.route != nil ? .heroSecond : .hero
                    }
                    return
                }
            }
    }
}

/// The featured poster's slow linear push-in to 108 % over its page's 9 s and the crossfade after it (Reduce Motion: no push)
private struct HeroPush: ViewModifier {
    @State private var isPushed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPushed && !reduceMotion ? 1.08 : 1)
            .onAppear {
                withAnimation(MotionCurve.linear.animation(HeroRotation.interval + MotionDuration.ambient)) { isPushed = true }
            }
    }
}

/// Home's first-load skeleton: the featured title's text and poster where the hero puts them, then a Continue Watching row
private struct TVHomeSkeleton: View {
    /// The parent's hold, which keeps the skeleton 500 ms once it shows
    @Binding var isHeld: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                SkeletonBlock(cornerRadius: 20)
                    .frame(width: 400, height: 600)
                    .padding(.top, 150)
                    .padding(.trailing, 120)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                VStack(alignment: .leading, spacing: 26) {
                    SkeletonBlock(cornerRadius: 6)
                        .frame(width: 360, height: 28)
                    SkeletonBlock(cornerRadius: 14)
                        .frame(width: 760, height: 96)
                    SkeletonBlock(cornerRadius: 6)
                        .frame(width: 480, height: 28)
                    SkeletonBlock(cornerRadius: 8)
                        .frame(width: 1000, height: 110)
                    SkeletonBlock(cornerRadius: 33)
                        .frame(width: 400, height: 66)
                        .padding(.top, 12)
                }
                .padding(.leading, 96)
                .padding(.top, 250)
            }
            .frame(maxWidth: .infinity, minHeight: 860, maxHeight: 860, alignment: .topLeading)
            // as many cards as the last load returned, and no row when it returned none
            let continueCount = SkeletonRows.count(for: "continue-watching", screenful: 4)
            if continueCount > 0 {
                VStack(alignment: .leading, spacing: 28) {
                    // section titles never skeleton
                    Text("Continue Watching")
                        .font(.system(size: 40, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Color.biingeText.opacity(0.7))
                        .padding(.leading, 96)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 48) {
                            ForEach(0..<continueCount, id: \.self) { _ in
                                SkeletonBlock(cornerRadius: 20)
                                    .frame(width: 520, height: 292)
                            }
                        }
                        .padding(.horizontal, 96)
                    }
                    .scrollDisabled(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .loadingSkeleton(isHeld: $isHeld)
    }
}
