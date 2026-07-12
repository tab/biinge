import SwiftUI

struct MovieDetailView: View {
    let movieId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(MovieStore.self) private var store

    @State private var details: MovieDetails?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if let details {
                content(details)
            } else if isLoading {
                ProgressView().tint(Color.biingePrimary)
                    .frame(maxWidth: .infinity).padding(.top, 100)
            } else {
                DetailLoadError()
            }
        }
        .background(Color.biingeBackground)
        .navigationTitle(details?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func content(_ movie: MovieDetails) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PosterImage(path: movie.posterPath, title: movie.title, size: "w342")
                .frame(width: 180)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title).font(.biingeTitle2).foregroundStyle(.primary)
                HStack(spacing: 10) {
                    if let rating = movie.rating, rating > 0 { RatingView(rating: rating) }
                    if let meta = metaLine(movie) {
                        Text(meta).font(.biingeFootnote).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            actions(movie)

            if !movie.overview.isEmpty {
                DetailSection(title: "Overview") {
                    Text(movie.overview).font(.biingeBody).foregroundStyle(.primary).padding(.horizontal)
                }
            }
            if !movie.credits.isEmpty {
                DetailSection(title: "Cast & Crew") { CreditsRow(credits: movie.credits) }
            }
            if !movie.recommendations.isEmpty {
                DetailSection(title: "Recommendations") {
                    RecommendationsRow(items: movie.recommendations) { .movie(id: $0) }
                }
            }
        }
        .padding(.bottom, 40)
    }

    private func actions(_ movie: MovieDetails) -> some View {
        let current = store.currentState(id: movieId)
        let pinned = store.isPinned(id: movieId)
        return HStack(spacing: 10) {
            ActionButton(title: "Want", systemImage: current == .want ? "bookmark.fill" : "bookmark", isActive: current == .want) {
                Task { await store.toggle(id: movieId, title: movie.title, posterPath: movie.posterPath, runtime: movie.runtime ?? 0, target: .want) }
            }
            ActionButton(title: "Watched", systemImage: current == .watched ? "checkmark.circle.fill" : "checkmark.circle", isActive: current == .watched) {
                Task { await store.toggle(id: movieId, title: movie.title, posterPath: movie.posterPath, runtime: movie.runtime ?? 0, target: .watched) }
            }
            if current != nil {
                ActionButton(title: pinned ? "Pinned" : "Pin", systemImage: pinned ? "pin.fill" : "pin", isActive: pinned) {
                    Task { await store.setPinned(id: movieId, pinned: !pinned) }
                }
            }
            if let key = movie.videos.first?.key {
                TrailerButton(videoKey: key)
            }
        }
        .padding(.horizontal)
    }

    private func metaLine(_ movie: MovieDetails) -> String? {
        var parts: [String] = []
        if let date = movie.releaseDate, date.count >= 4 { parts.append(String(date.prefix(4))) }
        if let runtime = movie.runtime, runtime > 0 { parts.append("\(runtime) min") }
        if let status = movie.status, !status.isEmpty { parts.append(status) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        details = try? await apiClient.movieDetails(id: movieId)
        isLoading = false
    }
}

/// Shared error state for detail screens (e.g. missing TMDB token → 422).
struct DetailLoadError: View {
    var body: some View {
        ContentUnavailableView(
            "Couldn't load details",
            systemImage: "exclamationmark.triangle",
            description: Text("Please try again.")
        )
        .padding(.top, 80)
    }
}
