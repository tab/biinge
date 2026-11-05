import Foundation

/// The episode a series' details offer next: the first aired episode biinge hasn't marked watched, else (caught up or fully watched) episode 1 of the first regular season
enum NextEpisodePick {
    /// The season whose episodes must load before the pick can settle
    case loading(season: Int)
    /// The episode to offer, aired, with its season number
    case episode(season: Int, EpisodeSummary)
    /// Nothing aired to offer (no regular season, or its first episode hasn't aired)
    case none

    /// Picks from the regular seasons in order (specials never count), skipping seasons biinge marks watched and episodes that haven't aired by today
    init(seasons: [SeasonSummary], episodes: [Int: [EpisodeSummary]], progress: WatchProgress?, today: Date = .now) {
        let regular = seasons.filter { $0.number > 0 }.sorted { $0.number < $1.number }
        let watchedSeasons = Set(progress?.watchedSeasons ?? [])
        // air dates are calendar days, compared as text with today's local day
        let day = today.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let isAired = { (episode: EpisodeSummary) in episode.airDate.map { !$0.isEmpty && $0.prefix(10) <= day } ?? false }
        let isWatched = { (episode: EpisodeSummary) in progress.map { $0.watchedEpisodes.contains(episode.id) } ?? episode.watched }
        for season in regular where !watchedSeasons.contains(season.id) {
            guard let list = episodes[season.number] else {
                self = .loading(season: season.number)
                return
            }
            let ordered = list.sorted { $0.number < $1.number }
            if let next = ordered.first(where: { isAired($0) && !isWatched($0) }) {
                self = .episode(season: season.number, next)
                return
            }
            // an unaired episode means the user is caught up, and later seasons hold nothing aired either
            if ordered.contains(where: { !isAired($0) }) { break }
        }
        guard let first = regular.first?.number else {
            self = .none
            return
        }
        guard let list = episodes[first] else {
            self = .loading(season: first)
            return
        }
        guard let opener = list.min(by: { $0.number < $1.number }), isAired(opener) else {
            self = .none
            return
        }
        self = .episode(season: first, opener)
    }

    /// The season the pick needs loaded or offers from, nil for none
    var season: Int? {
        switch self {
        case .loading(let season), .episode(let season, _): season
        case .none: nil
        }
    }

    /// The picked episode, nil while its season loads and for none
    var episode: EpisodeSummary? {
        if case .episode(_, let episode) = self { episode } else { nil }
    }

    /// The season the pick waits on whose last load failed, nil when none did or it's the shown season (whose error shows in place of its episodes)
    func failedSeason(failures: [Int: String], shown: Int?) -> Int? {
        guard case .loading(let season) = self, season != shown, failures[season] != nil else { return nil }
        return season
    }
}
