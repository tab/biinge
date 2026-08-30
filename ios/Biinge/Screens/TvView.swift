import SwiftUI

struct TvView: View {
    let store: TvStore
    @State private var selection: Segment = .watching
    @State private var didDeepLink = false
    @Environment(\.presentSeries) private var presentSeries
    @Environment(\.presentEpisode) private var presentEpisode

    enum Segment: String, CaseIterable {
        case want = "Want"
        case watching = "Watching"
        case watched = "Watched"
    }

    private var shows: [LibrarySeries] {
        switch selection {
        case .want: return store.wantShows
        case .watching: return store.watchingShows
        case .watched: return store.watchedShows
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selection) {
                    ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                content
            }
            .navigationTitle("TV Shows")
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

    @ViewBuilder
    private var content: some View {
        if store.isLoading && !store.hasLoaded {
            ProgressView().tint(Color.biingeLoader)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if shows.isEmpty {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "tv",
                description: Text("Shows you add will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PosterGrid(items: shows) { show in
                Button {
                    presentSeries(show.id)
                } label: {
                    PosterImage(path: show.posterPath, title: show.title)
                        .overlay(alignment: .topLeading) {
                            if show.state == .watching && show.episodesCount > 0 {
                                ProgressBadge(percent: show.progress * 100)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if show.pinned { PinBadge() }
                        }
                }
                .buttonStyle(.pressable)
                .detailTransitionSource("series-\(show.id)")
            }
            .refreshable { await store.load() }
        }
    }
}
