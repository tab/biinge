import SwiftUI

/// A biinge list (Want to Watch, Watching or Watched): the title and count, the Movies and TV Shows pills and the Sort menu over a poster grid
struct DesktopListsView: View {
    /// .want, .watching or .watched
    let section: DesktopSection
    let connection: JellyfinConnection
    /// Opens the search overlay (the empty state's action)
    let search: () -> Void

    @Environment(MovieStore.self) private var movieStore
    @Environment(SeriesStore.self) private var seriesStore
    /// The Movies pill, otherwise TV Shows
    @State private var showsMovies = true
    @State private var sort = ListSort.added
    /// The played share of each Jellyfin item with a resume position
    @State private var resume: [String: Double] = [:]
    /// Set while the last resume load failed, cleared by a later success
    @State private var resumeFailed = false
    /// Bumped by Retry, which reloads the resume positions
    @State private var resumeAttempt = 0
    /// The series whose removal waits for confirmation, as it deletes the show's episode marks
    @State private var removing: ListEntry?
    /// The last removal's confirmation with its Undo, nil when none shows
    @State private var toast: Toast?
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let movies = switch section {
        case .want: movieStore.wantMovies
        case .watched: movieStore.watchedMovies
        // movies have no Watching state
        default: [LibraryMovie]()
        }
        let series = switch section {
        case .want: seriesStore.wantSeries
        case .watching: seriesStore.watchingSeries
        default: seriesStore.watchedSeries
        }
        let hasPills = section != .watching
        let entries = hasPills && showsMovies
            ? ListEntry.entries(movies: movies, series: [], sort: sort)
            : ListEntry.entries(movies: [], series: series, sort: sort)
        let total = movies.count + series.count
        let sorts: [(ListSort, String)] = [(.added, "Date Added"), (.title, "Title")]
        let loadError = movieStore.loadError ?? seriesStore.loadError
        // typed apart, as the body is too long for the compiler to infer them in place
        let removal: AnyTransition = reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
        let reflow: Animation? = reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.emphasis)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(section.title)
                        .font(.system(size: 44, weight: .bold))
                        .tracking(-1.3)
                    if total > 0 {
                        Text(hasPills ? (total == 1 ? "1 title" : "\(total) titles") : (total == 1 ? "1 show" : "\(total) shows"))
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if hasPills {
                        HStack(spacing: 2) {
                            ForEach([(true, "Movies", movies.count), (false, "TV Shows", series.count)], id: \.0) { isMovies, label, count in
                                Button {
                                    // the fill slides in this transaction as the grid cuts, which Reduce Motion keeps for the crossfade
                                    withAnimation(MotionCurve.standard.animation(MotionDuration.standard)) { showsMovies = isMovies }
                                } label: {
                                    Text("\(label)  \(count)")
                                        .font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 15)
                                        .frame(height: 32)
                                        .foregroundStyle(showsMovies == isMovies ? Color.biingeText : Color.biingeText.opacity(0.72))
                                        .background {
                                            if showsMovies == isMovies {
                                                Capsule()
                                                    .fill(Color.biingeText.opacity(0.16))
                                                    // one shared fill slides between the pills, while a fill of each pill's own crossfades
                                                    .matchedGeometryEffect(id: reduceMotion ? AnyHashable(isMovies) : "selection", in: pill)
                                            }
                                        }
                                        .contentShape(Capsule())
                                }
                                .accessibilityAddTraits(showsMovies == isMovies ? .isSelected : [])
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                        .background(Color.biingeText.opacity(0.06), in: Capsule())
                    }
                    Spacer()
                    Menu {
                        Picker("Sort by", selection: $sort) {
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
                // a failed refresh keeps the lists an earlier load brought
                if let loadError {
                    HStack(spacing: 14) {
                        Label("Couldn’t load your lists. \(loadError.localizedDescription)", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(rgb: 0xFF8A8D))
                        Button("Retry") {
                            Task {
                                async let movies: Void = movieStore.load()
                                async let series: Void = seriesStore.load()
                                _ = await (movies, series)
                            }
                        }
                        .disabled(movieStore.isLoading || seriesStore.isLoading)
                    }
                } else if resumeFailed {
                    // the lists' own error line takes the place while it shows
                    HStack(spacing: 14) {
                        Label("Couldn’t load playback positions", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(rgb: 0xFF8A8D))
                        Button("Retry") { resumeAttempt += 1 }
                    }
                }
                // a pill switch cuts, like a sidebar switch, so old posters never cross the new ones (Reduce Motion crossfades them)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !isSkeletonHeld, !entries.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 22)], alignment: .leading, spacing: 30) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    NavigationLink(value: DesktopRoute.title(entry.title)) {
                                        ListCard(
                                            entry: entry,
                                            offServer: entry.isOffServer(connected: connection.isConnected) ? connection.serverName ?? "server" : nil,
                                            resume: entry.jellyfinID.flatMap { resume[$0] },
                                            showsProgress: section != .watched
                                        )
                                        .environment(\.posterFadeIndex, index)
                                    }
                                    .macMorphClick()
                                    .contextMenu {
                                        // the prototype pins only on the lists still to watch
                                        if section != .watched {
                                            Button(entry.pinned ? "Unpin" : "Pin") {
                                                switch entry.title {
                                                case .movie(let id): Task { await movieStore.setPinned(id: id, pinned: !entry.pinned) }
                                                case .series(let id): Task { await seriesStore.setPinned(id: id, pinned: !entry.pinned) }
                                                }
                                                toast = Toast(pinned: !entry.pinned)
                                            }
                                        }
                                        // Unwatched takes a title out of Watched, as Watched does on details
                                        Button(section == .watched ? "Mark as Unwatched" : "Mark as Watched") {
                                            switch entry.title {
                                            case .movie(let id):
                                                // the movie is on the list, so the store moves or removes it and never creates it (runtime goes unused)
                                                Task {
                                                    guard let change = await movieStore.change(
                                                        id: id, title: entry.name, posterPath: entry.posterPath, runtime: 0, jellyfinID: entry.jellyfinID,
                                                        to: section == .watched ? nil : .watched, connection: connection
                                                    ) else { return }
                                                    toast = change.toast
                                                    if let failure = await change.outcome.value { toast = failure }
                                                }
                                            case .series(let id):
                                                guard section != .watched else {
                                                    removing = entry
                                                    return
                                                }
                                                // the show is on the list, so the store moves it and never creates it (the counts and status go unused)
                                                Task {
                                                    guard let change = await seriesStore.change(
                                                        id: id, title: entry.name, posterPath: entry.posterPath, created: (0, 0, ""),
                                                        jellyfinID: entry.jellyfinID, to: .watched, connection: connection
                                                    ) else { return }
                                                    toast = change.toast
                                                    if let failure = await change.outcome.value { toast = failure }
                                                }
                                            }
                                        }
                                        Divider()
                                        Button("Remove from \(section.title)", role: .destructive) {
                                            switch entry.title {
                                            case .movie(let id):
                                                Task {
                                                    guard let change = await movieStore.change(
                                                        id: id, title: entry.name, posterPath: entry.posterPath, runtime: 0, jellyfinID: entry.jellyfinID,
                                                        to: nil, connection: connection
                                                    ) else { return }
                                                    toast = change.toast
                                                    if let failure = await change.outcome.value { toast = failure }
                                                }
                                            case .series:
                                                removing = entry
                                            }
                                        }
                                    }
                                    // Undo fades the poster back in as the gap opens
                                    .transition(.asymmetric(
                                        insertion: .opacity,
                                        removal: removal.animation(MotionCurve.exit.animation(MotionDuration.quick))
                                    ))
                                }
                            }
                            .buttonStyle(.plain)
                            // a removed poster shrinks out on Exit over Quick and the rest reflow over Emphasis (Reduce Motion fades it out and cuts to the new order)
                            .animation(reflow, value: entries.map(\.id))
                        } else if !isSkeletonHeld, loadError != nil {
                            // the error line above stands in for the empty state
                            EmptyView()
                        } else if isSkeletonHeld || !movieStore.hasLoaded || !seriesStore.hasLoaded {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 22)], alignment: .leading, spacing: 30) {
                                ForEach(0..<12, id: \.self) { _ in
                                    PosterSkeleton(cornerRadius: 10, caption: 14)
                                }
                            }
                            .loadingSkeleton(isHeld: $isSkeletonHeld)
                        } else {
                            let kind = showsMovies ? "movies" : "shows"
                            ContentUnavailableView {
                                switch section {
                                case .want: Label(total > 0 ? "No \(kind) in Want to Watch" : "Nothing in Want to Watch", systemImage: "bookmark")
                                case .watching: Label("No shows in progress", systemImage: "circle.lefthalf.filled")
                                default: Label(total > 0 ? "No \(kind) in Watched" : "Nothing watched yet", systemImage: "checkmark.circle")
                                }
                            } description: {
                                // the other pill holds titles, so the guidance points there
                                if total > 0 {
                                    Text("Switch to \(showsMovies ? "TV Shows" : "Movies"), or add \(kind) from search.")
                                } else {
                                    switch section {
                                    case .want: Text("Add movies and shows from search or any details page. The list is the same one you see on iPhone and Apple TV.")
                                    case .watching: Text("A show moves here when you start watching it on any device.")
                                    default: Text("Mark a title Watched and it shows up here, on iPhone and on Apple TV.")
                                    }
                                }
                            } actions: {
                                Button("Search the Catalog", action: search)
                            }
                            .padding(.vertical, 60)
                        }
                    }
                    .id("\(section.title)-\(showsMovies)")
                    .transition(reduceMotion ? .opacity : .identity)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .navigationTitle(section.title)
        .toast($toast)
        .confirmationDialog(
            "Remove \(removing?.name ?? "this show") from \(section.title)?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { entry in
            Button("Remove", role: .destructive) {
                guard case .series(let id) = entry.title else { return }
                Task {
                    guard let change = await seriesStore.change(
                        id: id, title: entry.name, posterPath: entry.posterPath, created: (0, 0, ""),
                        jellyfinID: entry.jellyfinID, to: nil, connection: connection
                    ) else { return }
                    toast = change.toast
                    if let failure = await change.outcome.value { toast = failure }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Biinge also deletes every episode you marked watched in this show.")
        }
        // each visit refreshes the lists, which brings the Jellyfin items of titles added since the last load
        .task(id: section) {
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

/// A list poster filling its column: the TMDB poster with the series' watched share, the pin and the resume bar or the "Not on" note, then the title
private struct ListCard: View {
    let entry: ListEntry
    /// The server name of the "Not on" note (nil when the server holds the title or Jellyfin isn't connected)
    let offServer: String?
    /// The played share of the movie's resume position, nil for none
    let resume: Double?
    /// Whether the series progress ring may show (a Watched series shows none, as on iPhone and Apple TV)
    let showsProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        PosterImage(title: entry.name, cornerRadius: 0, poster: Config.tmdbImageURL(path: entry.posterPath, size: "w342"),
                                    frame: proxy.size, titleFont: .system(size: 14), titlePadding: 12)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if showsProgress, let progress = entry.progress, progress > 0, progress < 1 {
                        PieChartView(percent: progress * 100)
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if entry.pinned { PinBadge() }
                }
                .overlay(alignment: .bottomLeading) {
                    // the mockup's white note and track over the art on any appearance
                    if let offServer {
                        Label("Not on \(offServer)", systemImage: "circle.slash")
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(8)
                    } else if let resume {
                        PlaybackBar(fraction: resume, inset: 8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.biingeText.opacity(0.07), lineWidth: 1))
                .posterHover(cornerRadius: 10)
                .macMorphSource(entry.title, url: Config.tmdbImageURL(path: entry.posterPath, size: "w342"))
            Text(entry.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
