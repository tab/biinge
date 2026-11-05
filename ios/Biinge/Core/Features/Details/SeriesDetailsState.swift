import Foundation
import JellyfinAPI
import Observation

/// A series' details screen state on every platform: the series, its seasons, the next episode it offers and their Jellyfin items, with the loads and Watched marks that change them
@MainActor
@Observable
final class SeriesDetailsState {
    private let apiClient: APIClient
    private let store: SeriesStore
    private let connection: JellyfinConnection
    /// The series' TMDB ID
    let seriesID: Int

    private(set) var details: SeriesDetails?
    /// The first load's error message, nil once the details are on screen and while a load runs
    private(set) var failure: String?
    /// Each season's episodes, load error and resume shares (every load starts them over)
    private(set) var seasons: SeasonEpisodes
    /// The season shown, nil until the first load picks one
    var season: Int?
    /// The next episode's Jellyfin item for its stored position, nil until it loads and when the library holds none
    private(set) var nextItem: BaseItemDto?
    /// The series' Jellyfin item for its played mark, nil until it loads and when the library holds none
    private(set) var seriesItem: BaseItemDto?
    /// The failed Watched mark's message, nil when no alert shows
    var watchedFailure: String?

    init(apiClient: APIClient, store: SeriesStore, connection: JellyfinConnection, seriesID: Int) {
        self.apiClient = apiClient
        self.store = store
        self.connection = connection
        self.seriesID = seriesID
        seasons = SeasonEpisodes(apiClient: apiClient, seriesID: seriesID)
    }

    /// The series' progress from the store, so marks made on any screen show here at once
    var progress: WatchProgress? {
        store.progress(id: seriesID)
    }

    /// What the series offers next, settling as the seasons it needs load
    var next: NextEpisodePick {
        NextEpisodePick(seasons: details?.seasons ?? [], episodes: seasons.episodes, progress: progress)
    }

    /// The next episode to play (nil while its season loads, and when nothing aired is left to offer)
    var nextEpisode: EpisodeSummary? {
        next.episode
    }

    /// The next episode's stored position in Jellyfin (0 until its item loads)
    var nextPosition: Int {
        nextItem?.id == nextEpisode?.jellyfinID ? nextItem?.userData?.playbackPositionTicks ?? 0 : 0
    }

    /// Whether biinge holds the offered episode as watched, which the pick offers only once the user is caught up (it then offers the opener)
    var isCaughtUp: Bool {
        guard let nextEpisode else { return false }
        return progress.map { $0.watchedEpisodes.contains(nextEpisode.id) } ?? nextEpisode.watched
    }

    /// The first episode of the loaded regular seasons still to air, with its season number (an episode without an air date counts; nil when none is listed)
    var upcoming: (season: Int, episode: EpisodeSummary)? {
        // air dates are calendar days, compared as text with today's local day, as the pick compares them
        let day = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        for season in (details?.seasons ?? []).filter({ $0.number > 0 }).sorted(by: { $0.number < $1.number }) {
            let ordered = (seasons.episodes[season.number] ?? []).sorted { $0.number < $1.number }
            if let episode = ordered.first(where: { ($0.airDate ?? "").isEmpty || $0.airDate?.prefix(10) ?? "" > day }) {
                return (season.number, episode)
            }
        }
        return nil
    }

    /// What the series' Jellyfin item offers now, which says whether the library holds the series at all
    var seriesPlay: DetailsPlay {
        DetailsPlay(jellyfinID: details?.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
    }

    /// What the next episode's Jellyfin item offers now
    var nextPlay: DetailsPlay {
        DetailsPlay(jellyfinID: nextEpisode?.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
    }

    /// The note on the next episode while the series plays on the server: its season or the episode alone missing there, or once caught up the next air date (nil otherwise)
    var episodeNote: PlayNote? {
        guard case .play = seriesPlay else { return nil }
        if case .episode(let number, let episode) = next, !isCaughtUp, episode.jellyfinID == nil {
            // the server lacks the whole season, or only this episode of it
            guard seasons.episodes[number]?.allSatisfy({ $0.jellyfinID == nil }) == true else {
                return PlayNote(play: .notOnServer, server: connection.serverName)
            }
            return .seasonNotOnServer(season: number, episode: episode.number, server: connection.serverName)
        }
        if isCaughtUp, let upcoming, let airDate = upcoming.episode.airDate {
            return .airs(season: upcoming.season, episode: upcoming.episode.number, airDate: airDate)
        }
        return nil
    }

    /// Loads the series and its progress from biinge, then the shown season and the next episode's; a failed first load keeps its error, and a failed reload keeps the details on screen
    func load() async {
        // every load starts the seasons over, so episodes cached before a connect lose their stale Jellyfin items
        seasons = SeasonEpisodes(apiClient: apiClient, seriesID: seriesID)
        failure = nil
        let started = store.episodeMarks[seriesID]
        // load the library too, as opened from Search the list pill would read an empty store
        async let libraryLoad: Void = store.loadIfNeeded()
        async let read = try? await apiClient.progress(seriesId: seriesID)
        do {
            let loaded = try await apiClient.seriesDetails(id: seriesID)
            details = loaded
            store.refreshMetadata(id: seriesID, title: loaded.title, posterPath: loaded.posterPath)
        } catch {
            // leaving the screen cancels the load, which is no failure
            if !Task.isCancelled, details == nil { failure = error.localizedDescription }
        }
        await libraryLoad
        guard let details else { return }
        // an episode mark made while the read was in flight is newer, so the read gives way to it
        if let fetched = await read, started == store.episodeMarks[seriesID] {
            store.apply(
                fetched, id: seriesID, title: details.title, posterPath: details.posterPath,
                episodesCount: details.totalEpisodesCount, pinned: details.pinned
            )
        }
        // the next episode's season, else the first season, keeping the one shown on a reload
        if season == nil { season = next.season ?? details.seasons.first?.number }
        if let season { await seasons.load(season) }
        // the next episode's season task keeps its ID across a reload, so its episodes load here
        if let number = next.season, number != season { await seasons.load(number) }
    }

    /// Loads the shown season's resume shares; a revoked token disconnects, and any other failure keeps the bars an earlier load brought
    func loadShares() async {
        guard let jellyfinID = details?.jellyfinID, let season, let service = connection.service else { return }
        do {
            try await seasons.loadShares(season: season, seriesItemID: jellyfinID, service: service)
        } catch {
            guard !Task.isCancelled else { return }
            _ = await connection.handleFailure(error)
        }
    }

    /// Loads the series' Jellyfin item for its played mark; a revoked token disconnects, and any other failure leaves the played note out
    func loadSeriesItem() async {
        guard let jellyfinID = details?.jellyfinID, let service = connection.service else { return }
        do {
            seriesItem = try await service.item(id: jellyfinID)
        } catch {
            guard !Task.isCancelled else { return }
            _ = await connection.handleFailure(error)
        }
    }

    /// Loads the next episode's Jellyfin item for its stored position; a revoked token disconnects, and any other failure leaves Play without Resume
    func loadNextItem() async {
        guard let jellyfinID = nextEpisode?.jellyfinID, let service = connection.service else { return }
        do {
            nextItem = try await service.item(id: jellyfinID)
        } catch {
            guard !Task.isCancelled else { return }
            _ = await connection.handleFailure(error)
        }
    }

    /// Marks or unmarks the episode through the store, which orders it with every screen's marks (returns whether it landed; a failure sets watchedFailure)
    @discardableResult
    func setWatched(_ watched: Bool, episode: EpisodeSummary, season: SeasonSummary, seasonEpisodes: [EpisodeSummary]) async -> Bool {
        guard let details else { return false }
        // Home hides a marked episode at once, as Jellyfin may still report it unplayed, then follows the store's progress once the write ends
        if let jellyfinID = episode.jellyfinID { connection.setWatched(itemID: jellyfinID, watched: watched) }
        var landed = true
        do {
            try await store.setEpisodeWatched(watched, episode: episode, season: season, seasonEpisodes: seasonEpisodes, details: details)
        } catch {
            landed = false
            watchedFailure = "Nothing changed. \(error.localizedDescription)"
        }
        if let jellyfinID = episode.jellyfinID {
            connection.setWatched(itemID: jellyfinID, watched: progress?.watchedEpisodes.contains(episode.id) ?? false)
        }
        return landed
    }

    /// Marks or unmarks the season through the store, which orders it with every screen's episode marks (returns whether it landed; a failure sets watchedFailure)
    @discardableResult
    func markSeason(_ season: SeasonSummary, episodes: [EpisodeSummary], watched: Bool) async -> Bool {
        guard let details else { return false }
        // Home hides the marked episodes at once, as Jellyfin may still report them unplayed, then follows the store's progress once the write ends
        for jellyfinID in episodes.compactMap(\.jellyfinID) { connection.setWatched(itemID: jellyfinID, watched: watched) }
        var landed = true
        do {
            try await store.setSeasonWatched(watched, season: season, seasonEpisodes: episodes, details: details)
        } catch {
            landed = false
            watchedFailure = "Nothing changed. \(error.localizedDescription)"
        }
        for episode in episodes {
            if let jellyfinID = episode.jellyfinID {
                connection.setWatched(itemID: jellyfinID, watched: progress?.watchedEpisodes.contains(episode.id) ?? false)
            }
        }
        return landed
    }
}
