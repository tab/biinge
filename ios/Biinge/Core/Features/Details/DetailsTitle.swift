import JellyfinAPI

/// A biinge details screen's title, by kind and TMDB ID
enum DetailsTitle: Hashable {
    case movie(Int)
    case series(Int)

    /// The details a Jellyfin movie or series opens (nil without a TMDB ID, and for any other kind)
    init?(_ item: BaseItemDto) {
        guard let id = item.providerIDs?["Tmdb"].flatMap({ Int($0) }) else { return nil }
        switch item.type {
        case .movie: self = .movie(id)
        case .series: self = .series(id)
        default: return nil
        }
    }

    /// The details any Jellyfin item opens, fetching the series of an episode or a season (nil without a TMDB ID)
    @MainActor
    static func resolve(_ item: BaseItemDto, service: any JellyfinService) async throws -> DetailsTitle? {
        guard item.type == .episode || item.type == .season else { return DetailsTitle(item) }
        // only the series item carries the series' TMDB ID
        guard let seriesID = item.seriesID else { return nil }
        return DetailsTitle(try await service.item(id: seriesID))
    }

    /// The biinge list holding the title, nil when biinge doesn't track it (poster badges read this, never Jellyfin's played state)
    @MainActor
    func state(movies: MovieStore, series: SeriesStore) -> WatchState? {
        switch self {
        case .movie(let id): movies.currentState(id: id)
        case .series(let id): series.currentState(id: id)
        }
    }
}

/// What a details screen's Play control offers for a title
enum DetailsPlay: Equatable {
    /// Plays the Jellyfin item with this ID
    case play(String)
    /// Asks to connect Jellyfin (this device has no connection, whatever the library holds)
    case connect
    /// Shows the "Not on server" note (connected, and the library holds no single item for the title)
    case notOnServer
    /// Shows the play of the Jellyfin item with this ID disabled (connected, and the server didn't answer the last call)
    case unreachable(String)

    init(jellyfinID: String?, isConnected: Bool, isUnreachable: Bool = false) {
        // without a connection the details can't tell what the server holds, so Connect comes first
        guard isConnected else {
            self = .connect
            return
        }
        // the biinge API names the item, so an unreachable server still tells a title it holds from one it lacks
        guard let jellyfinID else {
            self = .notOnServer
            return
        }
        self = isUnreachable ? .unreachable(jellyfinID) : .play(jellyfinID)
    }
}

/// The biinge Watched write a play Jellyfin reports as played needs
enum PlayedMark: Equatable {
    /// Marks the movie with this TMDB ID watched
    case movie(Int)
    /// Marks an episode watched by its season and episode numbers in the series with this TMDB ID
    case episode(series: Int, season: Int, episode: Int)

    /// The write for a played item and the details it resolves to (nil without a TMDB ID or episode numbers, for any other kind, and for a movie biinge already holds as watched)
    init?(_ item: BaseItemDto, title: DetailsTitle?, isWatchedMovie: (Int) -> Bool) {
        switch (item.type, title) {
        case (.movie, .movie(let id)):
            // a write for a watched movie would toggle it off
            guard !isWatchedMovie(id) else { return nil }
            self = .movie(id)
        case (.episode, .series(let id)):
            guard let season = item.parentIndexNumber, let episode = item.indexNumber else { return nil }
            self = .episode(series: id, season: season, episode: episode)
        default:
            return nil
        }
    }

    /// Writes the mark through the stores as the details screens do (an episode biinge already holds as watched writes nothing and refreshes the show's progress)
    @MainActor
    func write(apiClient: APIClient, movies: MovieStore, series: SeriesStore) async throws {
        switch self {
        case .movie(let id):
            // the store keeps biinge's title and TMDB poster, which the Jellyfin item doesn't carry
            let details = try await apiClient.movieDetails(id: id)
            // checked again after the fetch, since toggling a movie that became watched meanwhile would remove it
            guard movies.currentState(id: id) != .watched else { return }
            await movies.toggle(id: id, title: details.title, posterPath: details.posterPath, runtime: details.runtime ?? 0, target: .watched)
        case .episode(let seriesID, let seasonNumber, let episodeNumber):
            // the mark's body carries the series, season and episode metadata, as on the details screens
            async let seriesDetails = apiClient.seriesDetails(id: seriesID)
            async let seasonEpisodes = apiClient.seasonDetails(seriesId: seriesID, season: seasonNumber)
            let (details, seasonDetails) = try await (seriesDetails, seasonEpisodes)
            guard let season = details.seasons.first(where: { $0.number == seasonNumber }),
                  let episode = seasonDetails.episodes.first(where: { $0.number == episodeNumber }) else { return }
            guard !episode.watched else {
                // the season already reports it watched, so the store takes the API's progress instead of a second mark (unless a mark on the show is newer)
                let started = series.episodeMarks[seriesID]
                let progress = try await apiClient.progress(seriesId: seriesID)
                guard started == series.episodeMarks[seriesID] else { return }
                series.apply(progress, id: seriesID, title: details.title, posterPath: details.posterPath, episodesCount: details.totalEpisodesCount, pinned: details.pinned)
                return
            }
            let body = MarkEpisodeBody(
                series: ProgressSeries(title: details.title, posterPath: details.posterPath, seasonsCount: details.regularSeasonsCount,
                                       episodesCount: details.totalEpisodesCount, status: details.status ?? ""),
                season: ProgressSeasonMeta(title: season.title, number: season.number, episodesCount: season.episodesCount),
                episode: ProgressEpisodeMeta(title: episode.title, posterPath: episode.posterPath, runtime: episode.runtime, airDate: episode.airDate ?? "")
            )
            let progress = try await apiClient.markEpisode(seriesId: seriesID, seasonId: season.id, episodeId: episode.id, body)
            series.apply(progress, id: seriesID, title: details.title, posterPath: details.posterPath, episodesCount: details.totalEpisodesCount, pinned: details.pinned)
        }
    }
}
