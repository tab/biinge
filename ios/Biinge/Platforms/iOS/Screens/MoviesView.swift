import SwiftUI

struct MoviesView: View {
    let store: MovieStore
    let connection: JellyfinConnection
    /// Switches to Profile and opens its Jellyfin sheet (the Library's not connected action)
    let connectInProfile: () -> Void
    @State private var selection: Segment = .want
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("moviesSort") private var sort = ListSort.added
    /// The played share of each Jellyfin item with a resume position
    @State private var resume: [String: Double] = [:]
    /// Set while the last resume load failed, cleared by a later success
    @State private var resumeFailed = false
    /// Bumped by Retry, which reloads the resume positions
    @State private var resumeAttempt = 0
    @State private var didDeepLink = false
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(\.presentMovie) private var presentMovie
    @Environment(\.presentTitle) private var presentTitle

    enum Segment: String, CaseIterable {
        case want = "Want"
        case watched = "Watched"
        case library = "Library"
    }

    var body: some View {
        NavigationStack {
            // the chosen list cuts in, so old posters never cross the new ones (Reduce Motion crossfades them)
            ZStack {
                VStack(spacing: 0) {
                    if selection == .library {
                        MobileLibraryView(connection: connection, isMovies: true, connectInProfile: connectInProfile)
                    } else {
                        content
                    }
                }
                .id(selection)
                .transition(reduceMotion ? .opacity : .identity)
            }
            // title and pills move as one block, sliding away as the list scrolls up
            .modifier(CollapsingHeader {
                VStack(spacing: 8) {
                    Text("Movies").font(.biingeLargeTitle)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PillFilter(selection: $selection)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            })
            .background(Color.biingeBackground)
            .navigationTitle("Movies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                // the Library grid carries its own sort
                if selection != .library {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort by", selection: $sort) {
                                Text("Date Added").tag(ListSort.added)
                                Text("Title").tag(ListSort.title)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Sort")
                    }
                }
            }
            .upNextToolbar()
        }
        .task {
            await store.loadIfNeeded()
            #if DEBUG
            if !didDeepLink, let raw = ProcessInfo.processInfo.environment["DEBUG_MOVIE_ID"], let id = Int(raw) {
                didDeepLink = true
                presentMovie(id)
            }
            #endif
        }
        // one resume call covers every poster; a stopped play moves the positions
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

    @ViewBuilder
    private var content: some View {
        let entries = ListEntry.entries(movies: selection == .want ? store.wantMovies : store.watchedMovies, series: [], sort: sort)
        if let state = isSkeletonHeld ? .loading : LoadState(hasLoaded: store.hasLoaded, isEmpty: entries.isEmpty, loadError: store.loadError) {
            switch state {
            case .loading:
                PosterGridSkeleton(isHeld: $isSkeletonHeld)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t load your movies", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await store.load() } }
                        .buttonStyle(.glass)
                        .disabled(store.isLoading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "film",
                    description: Text("Movies you add will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // a failed refresh keeps the lists an earlier load brought, and its line takes the resume line's place
            if let loadError = store.loadError {
                ErrorBanner(message: "Couldn’t load your movies. \(loadError.localizedDescription)") {
                    Task { await store.load() }
                }
                .disabled(store.isLoading)
            } else if resumeFailed {
                ErrorBanner(message: "Couldn’t load playback positions") { resumeAttempt += 1 }
            }
            PosterGrid(items: entries) { entry in
                let offServer = entry.isOffServer(connected: connection.isConnected)
                Button {
                    presentTitle(entry.title, nil)
                } label: {
                    PosterImage(path: entry.posterPath, title: entry.name)
                        .overlay(alignment: .topTrailing) {
                            if entry.pinned { PinBadge() }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if offServer {
                                NotOnServerBadge(server: connection.serverName ?? "server")
                            } else if let share = entry.jellyfinID.flatMap({ resume[$0] }) {
                                PlaybackBar(fraction: share)
                            }
                        }
                }
                .buttonStyle(.pressable)
                .detailTransitionSource(entry.title)
            }
            .refreshable { await store.load() }
        }
    }
}
