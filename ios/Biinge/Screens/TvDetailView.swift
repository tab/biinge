import SwiftUI

struct TvDetailView: View {
    let seriesId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(TvStore.self) private var store

    @State private var details: SeriesDetails?
    @State private var progress: WatchProgress?
    @State private var isLoading = true

    private var watchedEpisodeIds: Set<Int> {
        Set(progress?.watchedEpisodes ?? [])
    }

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

    private func content(_ series: SeriesDetails) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PosterImage(path: series.posterPath, title: series.title, size: "w342")
                .frame(width: 180)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(series.title).font(.biingeTitle2).foregroundStyle(.primary)
                HStack(spacing: 10) {
                    if let rating = series.rating, rating > 0 { RatingView(rating: rating) }
                    if let meta = metaLine(series) {
                        Text(meta).font(.biingeFootnote).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            actions(series)

            if !series.overview.isEmpty {
                DetailSection(title: "Overview") {
                    Text(series.overview).font(.biingeBody).foregroundStyle(.primary).padding(.horizontal)
                }
            }
            if !series.credits.isEmpty {
                DetailSection(title: "Cast & Crew") { CreditsRow(credits: series.credits) }
            }
            if !series.seasons.isEmpty {
                DetailSection(title: "Seasons") {
                    VStack(spacing: 0) {
                        ForEach(series.seasons) { season in
                            SeasonDisclosureView(
                                season: season,
                                showId: seriesId,
                                watchedEpisodeIds: watchedEpisodeIds,
                                onToggle: markEpisode
                            )
                            Divider().padding(.leading)
                        }
                    }
                }
            }
            if !series.recommendations.isEmpty {
                DetailSection(title: "Recommendations") {
                    RecommendationsRow(items: series.recommendations) { .series(id: $0) }
                }
            }
        }
        .padding(.bottom, 40)
    }

    private func actions(_ series: SeriesDetails) -> some View {
        let current = store.currentState(id: seriesId)
        let pinned = store.isPinned(id: seriesId)
        return HStack(spacing: 10) {
            ActionButton(title: "Want", systemImage: current == .want ? "bookmark.fill" : "bookmark", isActive: current == .want) {
                Task {
                    await store.toggleWant(
                        id: seriesId, title: series.title, posterPath: series.posterPath,
                        seasonsCount: series.seasonsCount ?? 0, episodesCount: series.episodesCount ?? 0,
                        status: series.status ?? ""
                    )
                }
            }
            if current != nil {
                ActionButton(title: pinned ? "Pinned" : "Pin", systemImage: pinned ? "pin.fill" : "pin", isActive: pinned) {
                    Task { await store.setPinned(id: seriesId, pinned: !pinned) }
                }
                ActionButton(title: "Remove", systemImage: "trash", isActive: false) {
                    Task { await store.remove(id: seriesId) }
                }
            }
            if let key = series.videos.first?.key {
                TrailerButton(videoKey: key)
            }
        }
        .padding(.horizontal)
    }

    private func metaLine(_ series: SeriesDetails) -> String? {
        var parts: [String] = []
        if let date = series.releaseDate, date.count >= 4 { parts.append(String(date.prefix(4))) }
        if let count = series.seasonsCount, count > 0 { parts.append("\(count) season\(count == 1 ? "" : "s")") }
        if let status = series.status, !status.isEmpty { parts.append(status) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        async let detail = try? await apiClient.seriesDetails(id: seriesId)
        async let prog = try? await apiClient.progress(showId: seriesId)
        details = await detail
        progress = await prog
        isLoading = false
    }

    private func markEpisode(season: SeasonSummary, episode: EpisodeSummary, watched: Bool) async {
        guard let apiClient, let details else { return }
        let series = ProgressSeries(
            title: details.title,
            posterPath: details.posterPath,
            seasonsCount: details.seasonsCount ?? 0,
            episodesCount: details.episodesCount ?? 0,
            status: details.status ?? ""
        )
        do {
            let updated: WatchProgress
            if watched {
                let body = MarkEpisodeBody(
                    series: series,
                    season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                    episode: ProgressEpisodeMeta(title: episode.title, posterPath: episode.posterPath, runtime: episode.runtime, airDate: episode.airDate ?? "")
                )
                updated = try await apiClient.markEpisode(showId: seriesId, seasonId: season.id, episodeId: episode.id, body)
            } else {
                updated = try await apiClient.unmarkEpisode(showId: seriesId, seasonId: season.id, episodeId: episode.id)
            }
            progress = updated
            store.invalidate()
        } catch {
            // leave current progress; the row reflects the last known state
        }
    }
}

private struct SeasonDisclosureView: View {
    let season: SeasonSummary
    let showId: Int
    let watchedEpisodeIds: Set<Int>
    let onToggle: (SeasonSummary, EpisodeSummary, Bool) async -> Void

    @Environment(\.apiClient) private var apiClient
    @State private var episodes: [EpisodeSummary] = []
    @State private var isExpanded = false
    @State private var isLoading = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isLoading {
                ProgressView().tint(Color.biingePrimary).frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(episodes) { episode in
                        EpisodeRow(
                            showId: showId,
                            seasonNumber: season.number,
                            episode: episode,
                            isWatched: watchedEpisodeIds.contains(episode.id)
                        ) { watched in
                            await onToggle(season, episode, watched)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(season.title).font(.biingeCallout).foregroundStyle(.primary)
                Spacer()
                Text("\(season.episodesCount) ep").font(.biingeCaption2).foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .onChange(of: isExpanded) { _, expanded in
            if expanded && episodes.isEmpty {
                Task { await loadEpisodes() }
            }
        }
    }

    private func loadEpisodes() async {
        guard let apiClient else { return }
        isLoading = true
        episodes = (try? await apiClient.seasonDetails(showId: showId, season: season.number).episodes) ?? []
        isLoading = false
    }
}

private struct EpisodeRow: View {
    let showId: Int
    let seasonNumber: Int
    let episode: EpisodeSummary
    let isWatched: Bool
    let onToggle: (Bool) async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await onToggle(!isWatched) }
            } label: {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isWatched ? Color.biingePrimary : Color.biingeGrayDark)
            }
            .buttonStyle(.plain)

            NavigationLink(value: DetailRoute.episode(showId: showId, seasonNumber: seasonNumber, episodeNumber: episode.number)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(episode.number). \(episode.title)")
                            .font(.biingeFootnote).foregroundStyle(.primary).lineLimit(1)
                        if let airDate = episode.airDate, !airDate.isEmpty {
                            Text(airDate).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
    }
}
