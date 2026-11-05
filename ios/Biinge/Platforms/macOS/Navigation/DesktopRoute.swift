import Foundation
import JellyfinAPI

/// A screen pushed onto a Mac section's navigation stack
enum DesktopRoute: Hashable {
    /// A movie's or a series' biinge details, showing the Jellyfin poster of the tile they opened from in place of the TMDB one (nil for the TMDB poster)
    case title(DetailsTitle, poster: URL? = nil)
    case collection(BaseItemDto)
    /// A game's biinge details, by IGDB ID
    case game(id: Int)
    /// A person's biinge page, by TMDB ID
    case person(id: Int)
    /// A Home row's full list (its See All)
    case continueWatching, nextUp, recentlyAdded, collections
}
