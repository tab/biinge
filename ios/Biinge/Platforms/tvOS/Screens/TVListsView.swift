import SwiftUI

/// The My Lists tab: the biinge Want to Watch, Watching and Watched lists as poster rows, under a banner while Jellyfin isn't connected or can't be reached
struct TVListsView: View {
    let connection: JellyfinConnection

    @Environment(MovieStore.self) private var movieStore
    @Environment(SeriesStore.self) private var seriesStore
    /// The played share of each Jellyfin item with a resume position
    @State private var resume: [String: Double] = [:]
    /// Set while the last resume load failed, cleared by a later success
    @State private var resumeFailed = false
    /// Bumped by Retry, which reloads the resume positions
    @State private var resumeAttempt = 0
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false

    var body: some View {
        let offServer = connection.isConnected ? connection.serverName ?? "server" : nil
        Group {
            if !isSkeletonHeld, movieStore.hasLoaded && seriesStore.hasLoaded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 72) {
                        VStack(alignment: .leading, spacing: 32) {
                            HStack(alignment: .firstTextBaseline, spacing: 24) {
                                Text("My Lists")
                                    .font(.system(size: 76, weight: .bold))
                                    .tracking(76 * -0.03)
                                Text("From your Biinge account")
                                    .font(.system(size: 29))
                                    .foregroundStyle(Color.biingeText.opacity(0.55))
                            }
                            if !connection.isConnected {
                                HStack(spacing: 32) {
                                    Label("Jellyfin isn’t connected. Your lists still work. Connect it to play and to browse the library.", systemImage: "link")
                                        .font(.system(size: 29))
                                        .foregroundStyle(Color.biingeText.opacity(0.8))
                                    // clearing Not Now brings back the connect screen
                                    Button { connection.skippedConnect = false } label: {
                                        Label("Connect Jellyfin", systemImage: "link")
                                    }
                                    .buttonStyle(PillButtonStyle())
                                }
                                .focusSection()
                            } else if connection.isUnreachable {
                                HStack(spacing: 32) {
                                    Label("Can’t reach \(connection.serverName ?? "server"). Lists still work. Play comes back with the server.", systemImage: "icloud.slash")
                                        .font(.system(size: 29))
                                        .foregroundStyle(Color(rgb: 0xFF8A8D))
                                    Button {
                                        Task {
                                            await connection.checkReachability()
                                            // the positions failed with the server, so they load again with it
                                            resumeAttempt += 1
                                        }
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(PillButtonStyle())
                                }
                                .focusSection()
                            }
                            // a failed refresh keeps the lists an earlier load brought
                            if let loadError = movieStore.loadError ?? seriesStore.loadError {
                                HStack(spacing: 32) {
                                    Label("Couldn’t load your lists. \(loadError.localizedDescription)", systemImage: "exclamationmark.triangle")
                                        .font(.system(size: 29))
                                        .foregroundStyle(Color(rgb: 0xFF8A8D))
                                    Button {
                                        Task {
                                            async let movies: Void = movieStore.load()
                                            async let series: Void = seriesStore.load()
                                            _ = await (movies, series)
                                        }
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(PillButtonStyle())
                                    .disabled(movieStore.isLoading || seriesStore.isLoading)
                                }
                                .focusSection()
                            } else if resumeFailed, !connection.isUnreachable {
                                // the lists' own error line and the unreachable banner take the place while they show
                                Button { resumeAttempt += 1 } label: {
                                    Label("Couldn’t load playback positions · Retry", systemImage: "exclamationmark.triangle")
                                }
                                .buttonStyle(PillButtonStyle())
                                .focusSection()
                            }
                        }
                        .padding(.horizontal, 96)
                        ListRow(
                            title: "Want to Watch",
                            offServer: offServer,
                            resume: resume,
                            failed: movieStore.loadError != nil || seriesStore.loadError != nil,
                            entries: ListEntry.entries(movies: movieStore.wantMovies, series: seriesStore.wantSeries),
                            empty: "Nothing in Want to Watch. Add titles on iPhone, on Mac, or from any details page here."
                        )
                        ListRow(
                            title: "Watching",
                            offServer: offServer,
                            resume: resume,
                            failed: movieStore.loadError != nil || seriesStore.loadError != nil,
                            entries: ListEntry.entries(movies: [], series: seriesStore.watchingSeries),
                            empty: "No shows in progress. A show moves here when you start watching it."
                        )
                        ListRow(
                            title: "Watched",
                            showsProgress: false,
                            offServer: offServer,
                            resume: resume,
                            failed: movieStore.loadError != nil || seriesStore.loadError != nil,
                            entries: ListEntry.entries(movies: movieStore.watchedMovies, series: seriesStore.watchedSeries),
                            empty: "Nothing watched yet. Titles you mark Watched show up here."
                        )
                    }
                    // the tab bar keeps the header clear
                    .padding(.top, 170)
                    .padding(.bottom, 72)
                }
                .ignoresSafeArea()
            } else if !isSkeletonHeld, let loadError = movieStore.loadError ?? seriesStore.loadError {
                Message(icon: "icloud.slash", title: "Can’t reach Biinge", text: loadError.localizedDescription, action: "Retry") {
                    Task {
                        async let movies: Void = movieStore.load()
                        async let series: Void = seriesStore.load()
                        _ = await (movies, series)
                    }
                }
            } else {
                ListsSkeleton(isHeld: $isSkeletonHeld)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground.ignoresSafeArea())
        // each visit refreshes the lists, which brings the Jellyfin items of titles added since the last load
        .task {
            async let movies: Void = movieStore.load()
            async let series: Void = seriesStore.load()
            _ = await (movies, series)
        }
        // a stopped play moves the resume positions
        .task(id: "\(connection.userID ?? "")-\(connection.playbackEnded)-\(resumeAttempt)") {
            guard let service = connection.service else {
                resume = [:]
                resumeFailed = false
                return
            }
            do {
                // shortcut: the first 200 resume items only; page through the list if a library resumes more
                resume = ListEntry.resumeShares(try await service.page(of: .continueWatching, startIndex: 0, limit: 200).items)
                resumeFailed = false
            } catch {
                // a failure keeps the bars an earlier load brought, and a revoked token disconnects instead of showing the error
                guard !Task.isCancelled else { return }
                resumeFailed = !(await connection.handleFailure(error))
            }
        }
    }
}

/// A titled row of list posters that scrolls sideways with focus, or a line of guidance while the list is empty
private struct ListRow: View {
    let title: String
    /// Whether the series progress ring may show (a Watched series shows none, as on iPhone and Mac)
    var showsProgress = true
    /// The server name of the "Not on" note for titles the server doesn't hold (nil while Jellyfin isn't connected)
    let offServer: String?
    /// The played share of each Jellyfin item with a resume position
    let resume: [String: Double]
    /// Set while the last load failed, when the error line above stands in for the empty text
    let failed: Bool
    let entries: [ListEntry]
    let empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-0.8)
                if !entries.isEmpty {
                    Text("\(entries.count)")
                        .font(.system(size: 29))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                }
            }
            .padding(.leading, 96)
            if entries.isEmpty {
                if !failed {
                    Text(empty)
                        .font(.system(size: 29))
                        .foregroundStyle(Color.biingeText.opacity(0.6))
                        .padding(.leading, 96)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 48) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            let kind = if case .movie = entry.title { "Movie" } else { "TV Show" }
                            let server = entry.isOffServer(connected: offServer != nil) ? offServer : nil
                            NavigationLink(value: TVRoute.title(entry.title)) {
                                PosterImage(title: entry.name, cornerRadius: 0, poster: Config.tmdbImageURL(path: entry.posterPath, size: "w500"),
                                            frame: CGSize(width: 260, height: 390), titleFont: .system(size: 26), titlePadding: 20)
                                    .overlay(alignment: .topLeading) {
                                        if showsProgress, let progress = entry.progress, progress > 0, progress < 1 {
                                            PieChartView(percent: progress * 100)
                                                .frame(width: 36, height: 36)
                                                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                                                .padding(12)
                                        }
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if entry.pinned {
                                            Image(systemName: "pin.fill")
                                                .font(.system(size: 20, weight: .semibold))
                                                .rotationEffect(.degrees(25))
                                                .foregroundStyle(Color(rgb: 0xF4F4F2))
                                                .frame(width: 44, height: 44)
                                                .background(.black.opacity(0.6), in: Circle())
                                                .padding(12)
                                        }
                                    }
                                    .overlay(alignment: .bottomLeading) {
                                        // the mockup's white mark and track over the art on any appearance
                                        if server != nil {
                                            Image(systemName: "circle.slash")
                                                .font(.system(size: 26, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.92))
                                                .frame(width: 46, height: 46)
                                                .background(.black.opacity(0.62), in: Circle())
                                                .padding(14)
                                        } else if let share = entry.jellyfinID.flatMap({ resume[$0] }) {
                                            PlaybackBar(fraction: share, height: 7, inset: 14)
                                        }
                                    }
                            }
                            .buttonStyle(TVCardButtonStyle(
                                width: 260,
                                height: 390,
                                cornerRadius: 16,
                                title: entry.name,
                                subtitle: server.map { "\(kind) · Not on \($0)" } ?? kind
                            ))
                            .environment(\.posterFadeIndex, index)
                        }
                    }
                    .padding(.horizontal, 96)
                }
                .scrollClipDisabled()
            }
        }
        .focusSection()
    }
}

/// The My Lists and Games skeleton: the header, then two rows of poster cards laid out like their rows
struct ListsSkeleton: View {
    /// The parent's hold, which keeps the skeleton 500 ms once it shows
    @Binding var isHeld: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 72) {
            SkeletonBlock(cornerRadius: 12)
                .frame(width: 640, height: 76)
                .padding(.horizontal, 96)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 28) {
                    SkeletonBlock(cornerRadius: 8)
                        .frame(width: 320, height: 40)
                        .padding(.leading, 96)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 48) {
                            ForEach(0..<7, id: \.self) { _ in
                                PosterSkeleton(cornerRadius: 16, caption: 29)
                                    .frame(width: 260)
                            }
                        }
                        .padding(.horizontal, 96)
                    }
                    .scrollDisabled(true)
                }
            }
        }
        // the tab bar keeps the header clear
        .padding(.top, 170)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .loadingSkeleton(isHeld: $isHeld)
    }
}
