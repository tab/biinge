import SwiftUI

struct SeriesView: View {
    let store: SeriesStore
    let connection: JellyfinConnection
    /// Switches to Profile and opens its Jellyfin sheet (the Library's not connected action)
    let connectInProfile: () -> Void
    /// Switches to the Search tab (the empty Want list's action)
    let search: () -> Void
    @State private var selection: Segment = .watching
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("tvSort") private var sort = ListSort.added
    @State private var didDeepLink = false
    /// Set while a shown skeleton holds its 500 ms
    @State private var isSkeletonHeld = false
    @Environment(\.presentSeries) private var presentSeries
    @Environment(\.presentEpisode) private var presentEpisode
    @Environment(\.presentTitle) private var presentTitle

    enum Segment: String, CaseIterable {
        case want = "Want"
        case watching = "Watching"
        case watched = "Watched"
        case library = "Library"
    }

    private var series: [LibrarySeries] {
        switch selection {
        case .want: return store.wantSeries
        case .watching: return store.watchingSeries
        case .watched, .library: return store.watchedSeries
        }
    }

    var body: some View {
        NavigationStack {
            // the chosen list cuts in, so old posters never cross the new ones (Reduce Motion crossfades them)
            ZStack {
                VStack(spacing: 0) {
                    if selection == .library {
                        MobileLibraryView(connection: connection, isMovies: false, connectInProfile: connectInProfile)
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
                    Text("TV Shows").font(.biingeLargeTitle)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PillFilter(selection: $selection)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            })
            .background(Color.biingeBackground)
            .navigationTitle("TV Shows")
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
            if !didDeepLink, let raw = ProcessInfo.processInfo.environment["DEBUG_SERIES_ID"], let id = Int(raw) {
                didDeepLink = true
                presentSeries(id)
            } else if !didDeepLink, let raw = ProcessInfo.processInfo.environment["DEBUG_EPISODE"] {
                let parts = raw.split(separator: ":").compactMap { Int($0) }
                if parts.count == 3 {
                    didDeepLink = true
                    presentEpisode(parts[0], parts[1], parts[2])
                }
            }
            #endif
        }
    }

    // a series has no resume position of its own (Jellyfin resumes its episodes), so TV posters show no playback bar
    @ViewBuilder
    private var content: some View {
        let entries = ListEntry.entries(movies: [], series: series, sort: sort)
        if let state = isSkeletonHeld ? .loading : LoadState(hasLoaded: store.hasLoaded, isEmpty: entries.isEmpty, loadError: store.loadError) {
            switch state {
            case .loading:
                PosterGridSkeleton(isHeld: $isSkeletonHeld)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t load your shows", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await store.load() } }
                        .buttonStyle(.glass)
                        .disabled(store.isLoading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                ContentUnavailableView {
                    Label("Nothing here yet", systemImage: "tv")
                } description: {
                    Text("Shows you add will appear here.")
                } actions: {
                    if selection == .want {
                        Button("Search shows", systemImage: "magnifyingglass", action: search)
                            .buttonStyle(.glass)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // a failed refresh keeps the lists an earlier load brought
            if let loadError = store.loadError {
                ErrorBanner(message: "Couldn’t load your shows. \(loadError.localizedDescription)") {
                    Task { await store.load() }
                }
                .disabled(store.isLoading)
            }
            PosterGrid(items: entries) { entry in
                let offServer = entry.isOffServer(connected: connection.isConnected)
                Button {
                    presentTitle(entry.title, nil)
                } label: {
                    PosterImage(path: entry.posterPath, title: entry.name)
                        .overlay(alignment: .topLeading) {
                            if selection == .watching, let progress = entry.progress, progress > 0, progress < 1 {
                                ProgressBadge(percent: progress * 100)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if entry.pinned { PinBadge() }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if offServer {
                                NotOnServerBadge(server: connection.serverName ?? "server")
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
