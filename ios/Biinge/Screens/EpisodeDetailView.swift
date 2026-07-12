import SwiftUI

struct EpisodeDetailView: View {
    let showId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    @Environment(\.apiClient) private var apiClient

    @State private var details: EpisodeDetails?
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
        .navigationTitle(details?.title ?? "Episode")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func content(_ episode: EpisodeDetails) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            StillImage(path: episode.posterPath, title: episode.title)
                .padding(.horizontal)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Episode \(episode.number)")
                    .font(.biingeFootnote).foregroundStyle(Color.biingePrimary)
                Text(episode.title).font(.biingeTitle3).foregroundStyle(.primary)
                HStack(spacing: 10) {
                    if let rating = episode.rating, rating > 0 { RatingView(rating: rating) }
                    if let airDate = episode.airDate, !airDate.isEmpty {
                        Text(airDate).font(.biingeFootnote).foregroundStyle(.secondary)
                    }
                    if episode.runtime > 0 {
                        Text("\(episode.runtime) min").font(.biingeFootnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            if let key = episode.videos.first?.key {
                HStack { TrailerButton(videoKey: key) }.padding(.horizontal)
            }
            if !episode.overview.isEmpty {
                DetailSection(title: "Overview") {
                    Text(episode.overview).font(.biingeBody).foregroundStyle(.primary).padding(.horizontal)
                }
            }
            if !episode.credits.isEmpty {
                DetailSection(title: "Cast & Crew") { CreditsRow(credits: episode.credits) }
            }
        }
        .padding(.bottom, 40)
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        details = try? await apiClient.episodeDetails(showId: showId, season: seasonNumber, episode: episodeNumber)
        isLoading = false
    }
}

/// A 16:9 still image (episode/backdrop) with a gray + title fallback.
struct StillImage: View {
    let path: String
    let title: String

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.biingeSecondaryCard)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let url = Config.tmdbImageURL(path: path, size: "w780") {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(Color.biingeGrayDark)
                    }
                } else {
                    Text(title).font(.biingeFootnote).foregroundStyle(Color.biingeGrayDark)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
