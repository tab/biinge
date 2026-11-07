import Foundation
import JellyfinAPI

/// A title Home's featured row shows
struct HomeHero {
    /// The most titles the featured row holds
    static let limit = 5

    let item: BaseItemDto
    /// Whether the item comes from Continue Watching rather than Recently Added
    let isResume: Bool

    /// The featured row: Continue Watching in its order, then the recently added movies and shows newest added first, each title once, five at most and only titles a Play or Details can open
    static func featured(continueWatching: [BaseItemDto], recentlyAdded: [BaseItemDto]) -> [HomeHero] {
        // an item without a date added sorts after one with a date
        let recent = recentlyAdded.sorted { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
        var seen: Set<String> = []
        var heroes: [HomeHero] = []
        for (item, isResume) in continueWatching.map({ ($0, true) }) + recent.map({ ($0, false) }) {
            // a movie or series without a TMDB ID has no details and nothing to play, so its page would have no working button
            guard item.type == .episode || DetailsTitle(item) != nil else { continue }
            // an episode stands for its series, so a resumed episode and its recently added series feature once
            guard let key = item.type == .episode ? item.seriesID : item.id, seen.insert(key).inserted else { continue }
            heroes.append(HomeHero(item: item, isResume: isResume))
            if heroes.count == limit { break }
        }
        return heroes
    }
}

extension HomeHero {
    /// Drops the items biinge marked watched on this device from Continue Watching, Next Up and the series heroes' next up episodes (by Jellyfin item ID, as Jellyfin may still report them unplayed and resumable)
    static func hideWatched(_ watchedIDs: Set<String>, continueWatching: inout [BaseItemDto], nextUp: inout [BaseItemDto], heroNextUps: inout [String: BaseItemDto]) {
        continueWatching.removeAll { $0.id.map(watchedIDs.contains) == true }
        nextUp.removeAll { $0.id.map(watchedIDs.contains) == true }
        heroNextUps = heroNextUps.filter { $0.value.id.map(watchedIDs.contains) != true }
    }
}
