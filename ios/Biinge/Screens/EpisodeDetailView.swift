import SwiftUI

struct EpisodeDetailView: View {
    let showId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(TvStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var episode: EpisodeDetails?
    @State private var series: SeriesDetails?
    @State private var isLoading = true
    /// Serializes writes and versions optimistic mutations so only the newest applies state
    @State private var progressWrites: Task<Void, Never>?
    @State private var progressGeneration = 0

    /// Progress lives in the store, shared with the show detail underneath this sheet
    private var progress: WatchProgress? {
        store.progress(id: showId)
    }

    private var season: SeasonSummary? {
        series?.seasons.first { $0.number == seasonNumber }
    }

    private var isWatched: Bool {
        guard let episode else { return false }
        // Prefer live store progress (reflects optimistic toggles); fall back to the
        // server-provided flag when the sheet is opened without progress loaded
        if let progress { return progress.watchedEpisodes.contains(episode.id) }
        return episode.watched
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                if let episode {
                    content(episode)
                } else if isLoading {
                    ProgressView().tint(Color.biingeLoader)
                        .frame(maxWidth: .infinity).padding(.top, 160)
                } else {
                    DetailLoadError()
                }
            }
            .scrollIndicators(.hidden)

            closeButton
        }
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func content(_ ep: EpisodeDetails) -> some View {
        VStack(spacing: 0) {
            PosterImage(path: ep.posterPath, title: ep.title, size: "w780", cornerRadius: 12)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.7 }
                .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                .overlay(alignment: .bottomTrailing) {
                    if let key = ep.videos.first?.key {
                        playButton(key).padding(12)
                    }
                }
                .padding(.top, 64)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Episode \(ep.number)")
                            .font(.biingeFootnote).foregroundStyle(Color.biingePrimary)
                        Text(ep.title).font(.biingeTitle2).foregroundStyle(.primary)
                    }
                    Spacer(minLength: 12)
                    if let rating = ep.rating, rating > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(Color.biingePrimary)
                            Text(String(format: "%.1f", rating)).font(.system(size: 24, weight: .heavy)).foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 15)

                if season != nil {
                    Button {
                        Task { await toggleWatched(ep) }
                    } label: {
                        Text(isWatched ? "Remove Watched" : "Watched")
                            .font(.biingeCallout).fontWeight(.semibold)
                            .foregroundStyle(Color.biingeBackground)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Color.biingeText, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 15)
                }

                if !ep.overview.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Synopsis").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray)
                        Text(ep.overview).font(.biingeBody).foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 15)
                }

                if !ep.credits.isEmpty {
                    DetailSection(title: "Cast and crew") { CreditsRow(credits: ep.credits) }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCardBackground()
        }
    }

    private func playButton(_ key: String) -> some View {
        Button {
            if let url = URL(string: "https://www.youtube.com/watch?v=\(key)") { openURL(url) }
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5), in: Circle())
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Close")
        .padding(.leading, 16)
        .padding(.top, 16)
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        async let libraryLoad: Void = store.loadIfNeeded()
        async let episodeResult = try? await apiClient.episodeDetails(showId: showId, season: seasonNumber, episode: episodeNumber)
        async let seriesResult = try? await apiClient.seriesDetails(id: showId)
        episode = await episodeResult
        series = await seriesResult
        isLoading = false
        await libraryLoad
        // The episode payload carries its own watched flag, so only fetch progress to
        // seed the store when it isn't already loaded (e.g. opened via deep link)
        if series != nil, store.progress(id: showId) == nil,
           let fetched = try? await apiClient.progress(showId: showId) {
            setProgress(fetched)
        }
    }

    private func toggleWatched(_ ep: EpisodeDetails) async {
        guard let apiClient, let series, let season else { return }
        let watched = !isWatched
        let base = progress ?? WatchProgress(
            id: showId,
            state: store.currentState(id: showId) ?? .none,
            trackedState: store.currentState(id: showId),
            watchedSeasons: [],
            watchedEpisodes: []
        )
        // no episode list here, so season completeness on mark is reconciled by the server
        let optimistic = base.togglingEpisode(
            id: ep.id, watched: watched, seasonId: season.id,
            totalEpisodesCount: series.episodesCount,
            showStatus: series.status
        )
        let seriesMeta = ProgressSeries(
            title: series.title,
            posterPath: series.posterPath,
            seasonsCount: series.seasonsCount ?? 0,
            episodesCount: series.episodesCount ?? 0,
            status: series.status ?? ""
        )

        progressGeneration += 1
        let generation = progressGeneration
        let snapshot = progress
        setProgress(optimistic)

        let prior = progressWrites
        progressWrites = Task {
            await prior?.value
            do {
                let updated: WatchProgress
                if watched {
                    let body = MarkEpisodeBody(
                        series: seriesMeta,
                        season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                        episode: ProgressEpisodeMeta(title: ep.title, posterPath: ep.posterPath, runtime: ep.runtime, airDate: ep.airDate ?? "")
                    )
                    updated = try await apiClient.markEpisode(showId: showId, seasonId: season.id, episodeId: ep.id, body)
                } else {
                    updated = try await apiClient.unmarkEpisode(showId: showId, seasonId: season.id, episodeId: ep.id)
                }
                guard generation == progressGeneration else { return }
                setProgress(updated)
            } catch {
                guard generation == progressGeneration else { return }
                // Prefer server truth; fall back to the pre-mutation snapshot offline
                if let fresh = try? await apiClient.progress(showId: showId), generation == progressGeneration {
                    setProgress(fresh)
                } else if generation == progressGeneration, let snapshot {
                    setProgress(snapshot)
                }
            }
        }
    }

    /// One funnel into the store: this screen's button, the show detail underneath, and the grid
    private func setProgress(_ value: WatchProgress) {
        guard let series else { return }
        store.apply(
            value, id: showId,
            title: series.title, posterPath: series.posterPath,
            episodesCount: series.episodesCount ?? 0, pinned: series.pinned
        )
    }
}
