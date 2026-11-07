import JellyfinAPI
import SwiftUI

/// The user's ready-to-watch queue: Jellyfin's Continue Watching and Next Up, then aired episodes, released movies and released games from what they've pinned
struct UpNextView: View {
    @Environment(UpNextStore.self) private var store
    @Environment(\.apiClient) private var apiClient
    @Environment(\.presentSeries) private var presentSeries
    @Environment(\.presentMovie) private var presentMovie
    @Environment(\.presentTitle) private var presentTitle
    @Environment(\.presentLibraryTitle) private var presentLibraryTitle
    @Environment(\.presentGame) private var presentGame
    @Environment(\.attemptPlay) private var attemptPlay
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            content

            CloseButton()
        }
        .background(Color.biingeBackground)
        // the queue turns over as episodes air and the user watches them, so every open refreshes, and so does a stopped play;
        // the previous queue stays on screen meanwhile
        .task(id: "\(store.connection.userID ?? "")-\(store.connection.playbackEnded)") { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch isSkeletonHeld ? .loading : store.state {
        case .loading:
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Up Next")
                        .font(.biingeTitle1)
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                    VStack(alignment: .leading, spacing: 28) {
                        // as many Continue Watching cards as the last load returned, and no section when it returned none
                        let continueCount = SkeletonRows.count(for: "continue-watching", screenful: 2)
                        if continueCount > 0 {
                            VStack(alignment: .leading, spacing: 12) {
                                // section titles never skeleton
                                sectionTitle("Continue Watching")
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(0..<continueCount, id: \.self) { _ in
                                        VStack(alignment: .leading, spacing: 8) {
                                            SkeletonBlock(cornerRadius: 10)
                                                .frame(width: 216, height: 122)
                                            SkeletonBlock(cornerRadius: 4)
                                                .frame(width: 150, height: 14)
                                        }
                                    }
                                }
                            }
                        }
                        // the queue's poster rows, whose section isn't known until the load lands
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                HStack(spacing: 12) {
                                    PosterSkeleton(cornerRadius: 10)
                                        .frame(width: 72)
                                    VStack(alignment: .leading, spacing: 8) {
                                        SkeletonBlock(cornerRadius: 4)
                                            .frame(width: 160, height: 15)
                                        SkeletonBlock(cornerRadius: 4)
                                            .frame(width: 110, height: 12)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .loadingSkeleton(isHeld: $isSkeletonHeld)
                }
                // pinned to the scroll view's width, so the cards run off the trailing edge as the loaded row's do
                .containerRelativeFrame(.horizontal, alignment: .leading)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .scrollDisabled(true)
        case .failed:
            ContentUnavailableView {
                Label("Couldn't load Up Next", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await store.load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        // the hasLoaded state never reports notConnected, as the tracked queue shows without Jellyfin
        case .empty, .notConnected:
            ContentUnavailableView(
                "Nothing on deck",
                systemImage: "calendar",
                description: Text("Pin a show you're watching, or a movie or game you want, and its next episode or release shows up here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case nil:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    Text("Up Next")
                        .font(.biingeTitle1)
                        .foregroundStyle(.primary)
                        .padding(.horizontal)

                    if let loadError = store.loadError {
                        ErrorBanner(message: "Couldn’t refresh Up Next. \(loadError.localizedDescription)") {
                            Task { await store.load() }
                        }
                        .disabled(store.isLoading)
                    }

                    ForEach(store.sections, id: \.title) { section in
                        switch section {
                        case .continueWatching(let items):
                            VStack(alignment: .leading, spacing: 12) {
                                sectionTitle(section.title)
                                    .padding(.horizontal)
                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: 12) {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                            // Continue Watching and Next Up can hold the same series, so each row names its own cells
                                            let source = "continue-\(item.id ?? "")"
                                            ContinueCard(connection: store.connection, item: item, source: source) {
                                                open(item, from: source)
                                            } play: {
                                                play(item)
                                            }
                                            .environment(\.posterFadeIndex, index)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .scrollIndicators(.hidden)
                            }
                        case .nextUp(let items):
                            self.section(section.title) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    let source = "next-up-\(item.id ?? "")"
                                    NextUpRow(connection: store.connection, item: item, source: source) {
                                        open(item, from: source)
                                    } play: {
                                        play(item)
                                    }
                                    .environment(\.posterFadeIndex, index)
                                }
                            }
                        case .episodes(let episodes):
                            self.section(section.title) {
                                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                                    Button {
                                        presentSeries(episode.seriesId)
                                    } label: {
                                        UpNextRow(
                                            posterPath: episode.seriesPosterPath,
                                            title: episode.seriesTitle,
                                            detail: episodeLabel(episode),
                                            date: UpNextDate.format(episode.airDate)
                                        )
                                    }
                                    .buttonStyle(.pressable)
                                    .detailTransitionSource("series-\(episode.seriesId)")
                                    .environment(\.posterFadeIndex, index)
                                }
                            }
                        case .movies(let movies):
                            self.section(section.title) {
                                ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                                    Button {
                                        presentMovie(movie.id)
                                    } label: {
                                        UpNextRow(
                                            posterPath: movie.posterPath,
                                            title: movie.title,
                                            detail: ratingText(movie.rating),
                                            date: UpNextDate.format(movie.releaseDate)
                                        )
                                    }
                                    .buttonStyle(.pressable)
                                    .detailTransitionSource("movie-\(movie.id)")
                                    .environment(\.posterFadeIndex, index)
                                }
                            }
                        case .games(let games):
                            self.section(section.title) {
                                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                                    Button {
                                        presentGame(game.id)
                                    } label: {
                                        UpNextRow(
                                            posterPath: game.posterPath,
                                            title: game.title,
                                            detail: ratingText(game.rating),
                                            date: UpNextDate.format(game.releaseDate),
                                            source: .igdb
                                        )
                                    }
                                    .buttonStyle(.pressable)
                                    .detailTransitionSource("game-\(game.id)")
                                    .environment(\.posterFadeIndex, index)
                                }
                            }
                        }
                    }
                }
                // pinned to the scroll view's width, because a page answering a pixel wider pans sideways
                .containerRelativeFrame(.horizontal, alignment: .leading)
                // clears the floating close button, the way every other modal seats its title
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .refreshable { await store.load() }
        }
    }

    /// Opens the item's details by its TMDB ID, growing out of the cell marked with `source` (an episode opens its series)
    private func open(_ item: BaseItemDto, from source: String) {
        Task {
            guard let service = store.connection.service else { return }
            do {
                // the details show the Jellyfin poster (an episode's series poster) in place of the card's art
                if let title = try await DetailsTitle.resolve(item, service: service) {
                    presentLibraryTitle(title, source, store.connection.posterURL(item, maxWidth: 720))
                }
            } catch {
                // a failed fetch opens nothing, and a revoked token disconnects
                _ = await store.connection.handleFailure(error)
            }
        }
    }

    /// Resolves the item by the one-match rule, then plays it or opens the details it names
    private func play(_ item: BaseItemDto) {
        attemptPlay {
            guard let apiClient else { return }
            try await PlayResolution.play(item, fromStart: false, connection: store.connection, apiClient: apiClient) { presentTitle($0, nil) }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.biingeSubhead)
            .foregroundStyle(Color.biingeText)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)

            content()
        }
        .padding(.horizontal)
    }

    private func episodeLabel(_ episode: UpNextEpisode) -> String {
        let code = "S\(episode.seasonNumber) · E\(episode.number)"
        return episode.title.isEmpty ? code : "\(code) · \(episode.title)"
    }

    private func ratingText(_ rating: Double?) -> String {
        guard let rating, rating > 0 else { return "" }
        return String(format: "★ %.1f", rating)
    }
}

/// A Jellyfin Next Up row: the episode's art, its series, name, code and runtime, and a play button (a tap elsewhere opens the series)
private struct NextUpRow: View {
    let connection: JellyfinConnection
    let item: BaseItemDto
    /// The ID the art marks as the source its series grows out of
    let source: String
    let open: () -> Void
    let play: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.biingeSurface)
                        .frame(width: 120, height: 68)
                        .overlay {
                            CachedImage(url: connection.landscapeURL(item, maxWidth: 400), maxPixel: 400) {
                                Text(item.seriesName ?? "")
                                    .font(.biingeCaption2)
                                    .foregroundStyle(Color.biingeGrayDark)
                                    .padding(6)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.biingeFill(0.07)))
                        .detailTransitionSource(source)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.seriesName ?? "")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.biingeTextSecondary)
                        Text(item.name ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.biingeText)
                        Text("\(episodeCode(item)) · \(duration(ticks: item.runTimeTicks ?? 0))")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.biingeTextSecondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("\(item.seriesName ?? ""), \(item.name ?? "")")
            Button(action: play) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.biingeText)
                    .frame(width: 38, height: 38)
                    .background(Color.biingeFill(0.1), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Play \(item.name ?? "")")
        }
    }
}

/// A shared Up Next row so shows, movies and games look identical: poster, title, a detail line, and a date
private struct UpNextRow: View {
    let posterPath: String
    let title: String
    let detail: String
    let date: String
    var source: PosterImage.Source = .tmdb

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(
                path: posterPath,
                title: title,
                source: source,
                size: source == .igdb ? "cover_big" : "w185",
                cornerRadius: 10
            )
            .frame(width: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.biingeHeadline)
                    .foregroundStyle(Color.biingeText)
                    .lineLimit(1)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.biingeFootnote)
                        .foregroundStyle(Color.biingeTextSecondary)
                        .lineLimit(2)
                }

                if !date.isEmpty {
                    Text(date)
                        .font(.biingeCaption2)
                        .foregroundStyle(Color.biingeTextSecondary)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

/// Formats a TMDB `yyyy-MM-dd` date string for display, falling back to the raw value
private enum UpNextDate {
    static func format(_ raw: String) -> String {
        guard let date = isoParser.date(from: raw) else { return raw }
        return displayFormatter.string(from: date)
    }

    private static let isoParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
