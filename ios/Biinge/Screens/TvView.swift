import SwiftUI

struct TvView: View {
    let store: TvStore
    @State private var selection: Segment = .watching

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
        }
        .task { await store.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && !store.hasLoaded {
            ProgressView().tint(Color.biingePrimary)
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
            .refreshable { await store.load() }
        }
    }
}
