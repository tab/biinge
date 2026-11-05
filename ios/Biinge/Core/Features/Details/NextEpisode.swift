import JellyfinAPI

/// The episodes before and after the playing one by season and episode number from the biinge season details, never by watched progress
struct EpisodeNeighbors {
    /// An episode next to the playing one, with its season number (only episodes the server holds, so jellyfinID is set)
    struct Neighbor {
        let season: Int
        let episode: EpisodeSummary
    }

    var previous: Neighbor?
    var next: Neighbor?

    init(previous: Neighbor? = nil, next: Neighbor? = nil) {
        self.previous = previous
        self.next = next
    }

    /// The nearest episode numbers around the one in its season, else the last episode of the season before or episode 1 of the season after (specials, season 0, never cross into the regular seasons)
    init(season: Int, episode: Int, seasons: [Int: [EpisodeSummary]]) {
        let own = seasons[season] ?? []
        let earlier = season > 0 ? seasons.keys.filter { $0 > 0 && $0 < season }.max() : nil
        let later = season > 0 ? seasons.keys.filter { $0 > season }.min() : nil
        let before = own.filter { $0.number < episode }.max { $0.number < $1.number }.map { Neighbor(season: season, episode: $0) }
            ?? earlier.flatMap { number in seasons[number]?.max { $0.number < $1.number }.map { Neighbor(season: number, episode: $0) } }
        let after = own.filter { $0.number > episode }.min { $0.number < $1.number }.map { Neighbor(season: season, episode: $0) }
            ?? later.flatMap { number in seasons[number]?.min { $0.number < $1.number }.map { Neighbor(season: number, episode: $0) } }
        // an episode the server doesn't hold can't play, so it counts as none
        previous = before?.episode.jellyfinID == nil ? nil : before
        next = after?.episode.jellyfinID == nil ? nil : after
    }

    /// Loads the playing episode's season, and the season before or after only when the episode opens or closes its own (none for a movie or on a failed load)
    @MainActor
    static func load(_ item: BaseItemDto, service: any JellyfinService, apiClient: APIClient) async -> EpisodeNeighbors {
        guard item.type == .episode, let season = item.parentIndexNumber, let episode = item.indexNumber,
              case .series(let id)? = try? await DetailsTitle.resolve(item, service: service),
              let details = try? await apiClient.seriesDetails(id: id),
              let own = try? await apiClient.seasonDetails(seriesId: id, season: season).episodes else { return EpisodeNeighbors() }
        var seasons = [season: own]
        let regular = details.seasons.map(\.number).filter { $0 > 0 }
        if season > 0, !own.contains(where: { $0.number < episode }), let earlier = regular.filter({ $0 < season }).max() {
            seasons[earlier] = try? await apiClient.seasonDetails(seriesId: id, season: earlier).episodes
        }
        if season > 0, !own.contains(where: { $0.number > episode }), let later = regular.filter({ $0 > season }).min() {
            seasons[later] = try? await apiClient.seasonDetails(seriesId: id, season: later).episodes
        }
        return EpisodeNeighbors(season: season, episode: episode, seasons: seasons)
    }
}

/// The next-episode card's countdown: it starts once in an episode's credits, ticks once a second and plays at zero, and Cancel ends it for the episode
struct NextEpisodeCountdown {
    /// The countdown's length in seconds
    static let length = 10
    /// How long before the end of the runtime the credits, and the card, begin
    static let credits: Double = 30

    /// Seconds left while the card shows, nil otherwise
    private(set) var remaining: Int?
    /// Set once the countdown played or was cancelled, so it never starts again in the same episode
    private var isFinished = false

    /// Starts the countdown on entering the credits of a known runtime, and hides it on leaving them
    mutating func update(position: Double, duration: Double) {
        let inCredits = duration > Self.credits && position >= duration - Self.credits
        if !inCredits {
            remaining = nil
        } else if remaining == nil, !isFinished {
            remaining = Self.length
        }
    }

    /// Counts one second down and returns true at zero, the moment the next episode plays
    mutating func tick() -> Bool {
        guard let remaining else { return false }
        guard remaining > 1 else {
            self.remaining = nil
            isFinished = true
            return true
        }
        self.remaining = remaining - 1
        return false
    }

    /// Hides the card and lets the credits play (Play Now cancels it too)
    mutating func cancel() {
        remaining = nil
        isFinished = true
    }
}
