import JellyfinAPI
import SwiftUI

/// Mac Home: the featured row, then rows of Jellyfin lists, with the empty library, offline and failed reload states
struct DesktopHomeView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient

    /// The rows, with movies and series together newest added first as the one recently added list
    @State private var feed: HomeFeed
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    /// The featured page on screen (clamped to the featured row, which a reload can shorten)
    @State private var featuredIndex = 0
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.macOpen) private var open
    @Environment(\.colorScheme) private var colorScheme

    init(connection: JellyfinConnection, apiClient: APIClient) {
        self.connection = connection
        self.apiClient = apiClient
        _feed = State(initialValue: HomeFeed(connection: connection, recentlyAdded: [(.recentlyAdded, 20)]))
    }

    var body: some View {
        Group {
            if !isSkeletonHeld, let rows = feed.rows {
                let heroes = feed.heroes
                if heroes.isEmpty && rows.nextUp.isEmpty && rows.collections.isEmpty {
                    message(
                        icon: "film.stack",
                        title: "Your library is empty",
                        text: "Add movies and shows to your Jellyfin server’s Movies and TV Shows libraries."
                    )
                } else {
                    page(rows, heroes: heroes)
                }
            } else if !isSkeletonHeld, let failure = feed.failure {
                message(icon: "icloud.slash", title: "Can’t reach \(connection.serverURL?.host() ?? "the server")", text: failure)
            } else {
                DesktopHomeSkeleton(isHeld: $isSkeletonHeld)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .navigationTitle("Home")
        .task { await feed.load() }
        // back from the player, once its stop report has gone out, the rows show the new positions
        .onChange(of: connection.playbackEnded) {
            Task { await feed.load() }
        }
        // a Watched mark hides its title at once, then the reload resolves the details of a hero it promoted
        .onChange(of: connection.watchedIDs) {
            Task { await feed.hideWatched() }
        }
    }

    private func page(_ rows: HomeFeed.Rows, heroes: [HomeHero]) -> some View {
        // the one recently added list holds movies and series together
        let recentlyAdded = rows.recentlyAdded.flatMap(\.items)
        return ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if !heroes.isEmpty {
                    heroView(heroes, index: min(featuredIndex, heroes.count - 1))
                }
                // a failed reload keeps the rows an earlier load brought
                if let reloadFailure = feed.reloadFailure {
                    HStack(spacing: 14) {
                        Label("Couldn’t refresh Home. \(reloadFailure)", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(rgb: 0xFF8A8D))
                        Button("Retry") {
                            Task { await feed.load() }
                        }
                        .buttonStyle(.automatic)
                    }
                    .padding(.horizontal, 40)
                }
                continueWatchingRow(rows.continueWatching)
                if !rows.nextUp.isEmpty {
                    row("Next Episodes", seeAll: .nextUp) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                            ForEach(Array(rows.nextUp.enumerated()), id: \.element.id) { index, item in
                                NextUpCard(connection: connection, apiClient: apiClient, item: item)
                                    .environment(\.posterFadeIndex, index)
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                }
                if !recentlyAdded.isEmpty {
                    row("Recently Added", seeAll: .recentlyAdded) {
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(Array(recentlyAdded.enumerated()), id: \.element.id) { index, item in
                                    let isSeries = item.type == .series
                                    VStack(alignment: .leading, spacing: 8) {
                                        PosterImage(title: item.name ?? "", cornerRadius: 0, poster: connection.posterURL(item, maxWidth: 328),
                                                    frame: CGSize(width: 164, height: 246), titleFont: .system(size: 14), titlePadding: 12)
                                            .trackedBadge(DetailsTitle(item))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .posterHover(cornerRadius: 10)
                                            .macMorphSource(DetailsTitle(item), url: connection.posterURL(item, maxWidth: 328))
                                            .environment(\.posterFadeIndex, index)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name ?? "")
                                                .font(.system(size: 14, weight: .semibold))
                                            Text(isSeries ? (item.childCount == 1 ? "1 Season" : "\(item.childCount ?? 0) Seasons") : item.productionYear.map(String.init) ?? "")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1)
                                    }
                                    .frame(width: 164, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .macCardActions {
                                        // a title without a TMDB ID opens nothing
                                        if let title = DetailsTitle(item) { open(.title(title, poster: connection.posterURL(item, maxWidth: 640))) }
                                    }
                                    .macItemMenu(item, connection: connection, apiClient: apiClient)
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                    }
                }
                if !rows.collections.isEmpty {
                    row("Collections", seeAll: .collections) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                            ForEach(rows.collections, id: \.id) { item in
                                NavigationLink(value: DesktopRoute.collection(item)) {
                                    DesktopCollectionTile(connection: connection, collection: item)
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 56)
        }
    }

    /// Continue Watching cards, which open their details on a click, hidden when empty
    @ViewBuilder
    private func continueWatchingRow(_ items: [BaseItemDto]) -> some View {
        if !items.isEmpty {
            row("Continue Watching", seeAll: .continueWatching) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            DesktopContinueCard(connection: connection, item: item)
                                .environment(\.posterFadeIndex, index)
                                .frame(width: 300)
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
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    /// A titled Home row with the See All link to its full list
    private func row(_ title: String, seeAll: DesktopRoute, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.5)
                Spacer()
                NavigationLink("See All", value: seeAll)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            content()
        }
    }

    /// The featured page at the index, with the previous and next arrows and the page dots under the poster when the row holds more than one title
    private func heroView(_ heroes: [HomeHero], index: Int) -> some View {
        let hero = heroes[index]
        let item = hero.item
        let title = (item.type == .episode ? item.seriesName : item.name) ?? ""
        let kind = item.type == .movie ? "Movie" : "TV Show"
        let genres = item.genres?.prefix(3).joined(separator: ", ") ?? ""
        let meta: [String] = switch item.type {
        case .episode: [episodeCode(item), item.name ?? ""]
        case .series: [item.productionYear.map(String.init) ?? "", item.childCount == 1 ? "1 Season" : "\(item.childCount ?? 0) Seasons", genres]
        default: [item.productionYear.map(String.init) ?? "", duration(ticks: item.runTimeTicks ?? 0), genres]
        }
        // a series plays its next up episode, and offers Details only without one
        let playable = item.type == .series ? item.id.flatMap { feed.heroNextUps[$0] } : item
        let canResume = (playable?.userData?.playbackPositionTicks ?? 0) > 0
        let route = (DetailsTitle(item) ?? item.id.flatMap { feed.heroTitles[$0] }).map { DesktopRoute.title($0, poster: connection.posterURL(item, maxWidth: 640)) }
        let poster = connection.posterURL(item, maxWidth: 512)
        return HStack(alignment: .bottom, spacing: 48) {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(hero.isResume ? "Continue Watching" : "Recently added") · \(kind)")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.75)
                Text(title)
                    .font(.system(size: 64, weight: .bold))
                    .tracking(-2.2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 14) {
                    Text(meta.filter { !$0.isEmpty }.joined(separator: " · "))
                        .opacity(0.8)
                    if let rating = item.communityRating {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.biingePrimary)
                            Text(rating, format: .number.precision(.fractionLength(1)))
                                .fontWeight(.semibold)
                        }
                    }
                }
                .font(.system(size: 15))
                Text(item.overview ?? "")
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .lineLimit(3)
                    .opacity(0.82)
                HStack(spacing: 12) {
                    if let playable {
                        Button {
                            attemptPlay { try await PlayResolution.play(playable, fromStart: false, connection: connection, apiClient: apiClient) { open(.title($0)) } }
                        } label: {
                            Label(canResume ? "Resume" : "Play", systemImage: "play.fill")
                                .padding(.horizontal, 22)
                                .frame(height: 40)
                                .foregroundStyle(Color.biingeBackground)
                                .background(Color.biingeText, in: Capsule())
                                .contentShape(Capsule())
                        }
                    }
                    if let route {
                        NavigationLink(value: route) {
                            Label("Details", systemImage: "info.circle")
                                .padding(.horizontal, 20)
                                .frame(height: 40)
                                .background(Color.biingeText.opacity(0.14), in: Capsule())
                                .contentShape(Capsule())
                        }
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 4)
            }
            .frame(maxWidth: 600, alignment: .leading)
            Spacer(minLength: 0)
            VStack(spacing: 20) {
                NavigationLink(value: route) {
                    PosterImage(title: title, cornerRadius: 0, poster: poster, frame: CGSize(width: 220, height: 330), titleFont: .system(size: 14), titlePadding: 12)
                        // an episode hero's title is the series its fetch resolved
                        .trackedBadge(DetailsTitle(item) ?? item.id.flatMap { feed.heroTitles[$0] })
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.biingeText.opacity(0.1), lineWidth: 1))
                        .shadow(color: Color.biingeShadow.opacity(0.55), radius: 30, y: 24)
                }
                if heroes.count > 1 {
                    FeaturedPager(count: heroes.count, index: index, selection: $featuredIndex)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 72)
        .padding(.bottom, 32)
        .background {
            // the poster blurred and dimmed behind the hero, fading into the page at the left and the bottom
            ZStack {
                Color.clear.overlay {
                    CachedImage(url: poster, maxPixel: 512) { Color.clear }
                        .blur(radius: 70)
                        .saturation(1.5)
                        // colorMultiply is CSS brightness(): it scales each channel instead of adding to it
                        .colorMultiply(Color.biingeBackdropBrightness)
                        // oversized so the blur's soft edge falls outside the hero
                        .padding(-120)
                }
                // light mode washes the art out so the hero's dark text reads over any artwork
                Color.biingeBackground.opacity(colorScheme == .light ? 0.7 : 0)
                LinearGradient(
                    stops: [.init(color: Color.biingeBackground.opacity(0.72), location: 0), .init(color: Color.biingeBackground.opacity(0.15), location: 0.65)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    stops: [.init(color: Color.biingeBackground.opacity(0), location: 0.45), .init(color: Color.biingeBackground, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
        }
    }

    /// The message state with Retry, which loads again
    private func message(icon: String, title: String, text: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(text)
        } actions: {
            Button("Retry") {
                Task { await feed.reload() }
            }
        }
    }
}

/// The featured row's previous and next arrows around its page dots, which turn to the page they show
private struct FeaturedPager: View {
    let count: Int
    /// The page on screen
    let index: Int
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 12) {
            Button {
                selection = (index + count - 1) % count
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .help("Previous")
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { page in
                    Button {
                        selection = page
                    } label: {
                        Capsule()
                            .fill(Color.biingeText.opacity(page == index ? 1 : 0.35))
                            .frame(width: page == index ? 22 : 6, height: 6)
                            // a taller hit area than the 6-point dot
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Featured title \(page + 1) of \(count)")
                    .accessibilityAddTraits(page == index ? .isSelected : [])
                }
            }
            Button {
                selection = (index + 1) % count
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .help("Next")
        }
        .foregroundStyle(Color.biingeText.opacity(0.7))
    }
}

/// A Next Up card filling the width it's given: the episode's art, its series, name, code and runtime, and a play button (a click opens the series, and the button plays)
struct NextUpCard: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let item: BaseItemDto

    /// Whether the card has keyboard focus, which its ring and fill show (the card has no hover look of its own)
    @FocusState private var isFocused: Bool
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.macOpen) private var open

    var body: some View {
        HStack(spacing: 16) {
            PosterImage(title: item.seriesName ?? "", cornerRadius: 0, poster: connection.landscapeURL(item, maxWidth: 384),
                        frame: CGSize(width: 192, height: 108), titleFont: .system(size: 14), titlePadding: 12)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.seriesName ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(item.name ?? "")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(episodeCode(item)) · \(duration(ticks: item.runTimeTicks ?? 0))")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
                    .background(Color.biingeText.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Play")
        }
        .padding(8)
        // a ring over a faint fill stands in for the card's system focus ring, which is off
        .background(Color.biingeText.opacity(isFocused ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.biingeText.opacity(isFocused ? 0.28 : 0), lineWidth: 1))
        .animation(MotionCurve.standard.animation(MotionDuration.quick), value: isFocused)
        .contentShape(Rectangle())
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
        .focused($isFocused)
        .macItemMenu(item, connection: connection, apiClient: apiClient)
    }

    /// Plays the episode by the one-match rule, or opens the details it resolves to
    private func play() {
        attemptPlay { try await PlayResolution.play(item, fromStart: false, connection: connection, apiClient: apiClient) { open(.title($0)) } }
    }
}

/// A Continue Watching card filling the width it's given: landscape art with the time left and a progress bar, then the title and the episode or year
struct DesktopContinueCard: View {
    let connection: JellyfinConnection
    let item: BaseItemDto

    var body: some View {
        let isEpisode = item.type == .episode
        let title = (isEpisode ? item.seriesName : item.name) ?? ""
        let left = (item.runTimeTicks ?? 0) - (item.userData?.playbackPositionTicks ?? 0)
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        PosterImage(title: title, cornerRadius: 0, poster: connection.landscapeURL(item, maxWidth: 600), frame: proxy.size, titleFont: .system(size: 14), titlePadding: 12)
                    }
                }
                .overlay {
                    LinearGradient(
                        stops: [.init(color: .black.opacity(0), location: 0.45), .init(color: .black.opacity(0.75), location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomLeading) {
                    // the mockup's white text and track over the darkened art on any appearance
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(duration(ticks: max(left, 0))) left")
                            .font(.system(size: 13, weight: .semibold))
                        Capsule()
                            .fill(.white.opacity(0.28))
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule().frame(width: proxy.size.width * min(max((item.userData?.playedPercentage ?? 0) / 100, 0), 1))
                                }
                            }
                            .frame(height: 4)
                    }
                    .foregroundStyle(Color(rgb: 0xF4F4F2))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 11)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .posterHover(cornerRadius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(isEpisode ? "\(episodeCode(item)) · \(item.name ?? "")" : "Movie · \(item.productionYear.map(String.init) ?? "")")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// A collection tile over its blurred centre poster: the collection's own poster, or a fan of its first three items' posters when it has none
struct DesktopCollectionTile: View {
    let connection: JellyfinConnection
    let collection: BaseItemDto

    @State private var items: [BaseItemDto] = []

    var body: some View {
        let own = collection.imageTags?[ImageType.primary.rawValue]
        let posters = own != nil ? [connection.posterURL(collection, maxWidth: 270)] : items.map { connection.posterURL($0, maxWidth: 270) }
        // the mockup's order: the second poster sits in the centre, the first on the left and the third (or the first) on the right
        let center = posters.count > 1 ? posters[1] : posters.isEmpty ? nil : posters[0]
        let left = posters.count > 1 ? posters[0] : nil
        let right = posters.count > 2 ? posters[2] : left
        let count = collection.childCount ?? 0
        // the tile is art with light text over it, so it stays dark on any appearance
        ZStack(alignment: .topTrailing) {
            Color(rgb: 0x17171D)
            Color.clear.overlay {
                CachedImage(url: center, maxPixel: 270) { Color.clear }
                    .blur(radius: 40)
                    .saturation(1.4)
                    .colorMultiply(Color(white: 0.5))
                    .padding(-60)
            }
            if let left {
                poster(left, width: 86, height: 129)
                    .rotationEffect(.degrees(-9))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 10)
                    .padding(.top, 40)
                    .padding(.trailing, 120)
            }
            if let right {
                poster(right, width: 86, height: 129)
                    .rotationEffect(.degrees(9))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 10)
                    .padding(.top, 40)
                    .padding(.trailing, 30)
            }
            if let center {
                poster(center, width: 90, height: 135)
                    .shadow(color: .black.opacity(0.6), radius: 15, y: 14)
                    .padding(.top, 28)
                    .padding(.trailing, 73)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .lineLimit(2)
                Text(count == 1 ? "1 title" : "\(count) titles")
                    .font(.system(size: 13))
                    .opacity(0.72)
            }
            .foregroundStyle(Color(rgb: 0xF4F4F2))
            .padding(.leading, 24)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 196)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .posterHover(cornerRadius: 16)
        .task {
            // three poster loads per tile only when the collection has no poster of its own
            guard own == nil, let service = connection.service, let id = collection.id else { return }
            items = (try? await service.page(of: .collection(id), startIndex: 0, limit: 3).items) ?? []
        }
    }

    private func poster(_ url: URL, width: CGFloat, height: CGFloat) -> some View {
        CachedImage(url: url, maxPixel: height * 2) { Color(rgb: 0x282828) }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Shows a toast over the detail column, which outlives the screen whose context menu started a removal
struct ToastAction: Equatable {
    let perform: @MainActor (Toast?) -> Void

    @MainActor func callAsFunction(_ toast: Toast?) {
        perform(toast)
    }

    // the writer's closure reads its state when it runs, so every action it makes does the same thing
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// Shows a toast over the detail column, which outlives the screen whose context menu started a removal
    @Entry var macToast = ToastAction { _ in }
}

extension View {
    /// Opens a card on a click, which never plays it (playback starts from the details, a hover Play or the right-click menu)
    func macCardActions(open: @escaping () -> Void) -> some View {
        onTapGesture(perform: open)
            .macMorphClick()
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
            // keyboard navigation reaches the card but a click doesn't focus it, and Return or Space opens it as a click does
            .focusable(interactions: .activate)
            // the card's own look shows the focus (a poster's lift, a Next Up card's ring and fill) in place of the system's square ring
            .focusEffectDisabled()
            .onKeyPress(keys: [.return, .space]) { _ in
                open()
                return .handled
            }
    }

    /// Adds the right-click menu of a poster or card: Play or Resume by the one-match rule, Start Over for a stored position, Open Details by TMDB ID, and biinge Want to Watch and Watched for a movie with a TMDB ID
    func macItemMenu(_ item: BaseItemDto, connection: JellyfinConnection, apiClient: APIClient) -> some View {
        modifier(ItemMenu(item: item, connection: connection, apiClient: apiClient))
    }
}

/// The context menu with the alert for a Want or Watched change that couldn't load the movie
private struct ItemMenu: ViewModifier {
    let item: BaseItemDto
    let connection: JellyfinConnection
    let apiClient: APIClient

    @Environment(\.macOpen) private var open
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.macToast) private var showToast
    @Environment(MovieStore.self) private var store
    /// The failed Want or Watched write's message, nil when no alert shows
    @State private var watchedFailure: String?
    /// The list the failed change was for, which the alert names
    @State private var failedList = "Watched"

    func body(content: Content) -> some View {
        // a series or a season offers no Start Over, as its Play opens its details
        let canResume = item.type != .series && item.type != .season && (item.userData?.playbackPositionTicks ?? 0) > 0
        // biinge tracks a movie by its TMDB ID, so only a movie with one offers Watched
        let movieID: Int? = switch DetailsTitle(item) {
        case .movie(let id): id
        default: nil
        }
        // an episode or a season opens its series, whose TMDB ID only a fetch of the series tells
        let isEpisode = item.type == .episode || item.type == .season
        content
            .contextMenu {
                Button(canResume ? "Resume" : "Play") {
                    attemptPlay { try await PlayResolution.play(item, fromStart: false, connection: connection, apiClient: apiClient) { open(.title($0)) } }
                }
                if canResume {
                    Button("Start Over") {
                        attemptPlay { try await PlayResolution.play(item, fromStart: true, connection: connection, apiClient: apiClient) { open(.title($0)) } }
                    }
                }
                if isEpisode {
                    Button("Open Details") {
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
                } else if let title = DetailsTitle(item) {
                    Button("Open Details") { open(.title(title, poster: connection.posterURL(item, maxWidth: 640))) }
                }
                if let movieID {
                    let isWant = store.currentState(id: movieID) == .want
                    let isWatched = store.currentState(id: movieID) == .watched
                    Divider()
                    Button(isWant ? "Remove from Want to Watch" : "Add to Want to Watch") {
                        Task { await change(tmdbID: movieID, to: isWant ? nil : .want, list: "Want to Watch") }
                    }
                    Button(isWatched ? "Remove from Watched" : "Mark as Watched") {
                        Task { await change(tmdbID: movieID, to: isWatched ? nil : .watched, list: "Watched") }
                    }
                }
            }
            .alert(
                "Couldn’t change \(failedList)",
                isPresented: Binding(get: { watchedFailure != nil }, set: { if !$0 { watchedFailure = nil } })
            ) {
                Button("OK") {}
            } message: {
                Text(watchedFailure ?? "")
            }
    }

    /// Moves the movie into `target` through MovieStore, whose new state its cards read at once, or removes it for nil, with its toast and Undo for a removal (a failed load of the movie shows the alert naming `list`)
    private func change(tmdbID: Int, to target: WatchState?, list: String) async {
        do {
            // the store keeps biinge's title and TMDB poster, which the Jellyfin item doesn't carry
            let details = try await apiClient.movieDetails(id: tmdbID)
            guard let change = await store.change(
                id: tmdbID, title: details.title, posterPath: details.posterPath, runtime: details.runtime ?? 0, jellyfinID: item.id,
                to: target, connection: connection
            ) else { return }
            showToast(change.toast)
            if let failure = await change.outcome.value { showToast(failure) }
        } catch {
            failedList = list
            watchedFailure = "Nothing changed. \(error.localizedDescription)"
        }
    }
}

/// Home's first-load skeleton: the featured title's text and poster, then the Continue Watching and Recently Added rows
private struct DesktopHomeSkeleton: View {
    /// The parent's hold, which keeps the skeleton 500 ms once it shows
    @Binding var isHeld: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                HStack(alignment: .bottom, spacing: 48) {
                    VStack(alignment: .leading, spacing: 18) {
                        SkeletonBlock(cornerRadius: 4)
                            .frame(width: 200, height: 14)
                        SkeletonBlock(cornerRadius: 10)
                            .frame(width: 440, height: 64)
                        SkeletonBlock(cornerRadius: 4)
                            .frame(width: 260, height: 15)
                        SkeletonBlock(cornerRadius: 6)
                            .frame(maxWidth: 600)
                            .frame(height: 66)
                        SkeletonBlock(cornerRadius: 20)
                            .frame(width: 220, height: 40)
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                    SkeletonBlock(cornerRadius: 14)
                        .frame(width: 220, height: 330)
                }
                .padding(.horizontal, 40)
                .padding(.top, 72)
                .padding(.bottom, 32)
                // as many cards as the last load returned, and no row when it returned none
                let continueCount = SkeletonRows.count(for: "continue-watching", screenful: 5)
                if continueCount > 0 {
                    VStack(alignment: .leading, spacing: 16) {
                        title("Continue Watching")
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(0..<continueCount, id: \.self) { _ in
                                    SkeletonBlock(cornerRadius: 10)
                                        .frame(width: 300, height: 169)
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    title("Recently Added")
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            ForEach(0..<8, id: \.self) { _ in
                                PosterSkeleton(cornerRadius: 10, caption: 14)
                                    .frame(width: 164)
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                }
            }
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .loadingSkeleton(isHeld: $isHeld)
    }

    /// A row's title as text in the row's own style, since section titles never skeleton
    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .bold))
            .tracking(-0.5)
            .padding(.horizontal, 40)
    }
}
