import Foundation
import JellyfinAPI

/// An audio or subtitle track's label in the players' track panels: the language, and the rest of Jellyfin's title below it (each platform renders its own row)
struct TrackLabel: Equatable {
    let title: String
    /// The rest of the title, nil when Jellyfin's title is the language alone
    let detail: String?
}

extension TrackLabel {
    /// Splits Jellyfin's "English - Dolby Digital - 5.1 - Default" into the language and "Dolby Digital · 5.1 · Default"
    init(_ track: MediaStream) {
        let parts = (track.displayTitle ?? "Track \(track.index ?? 0)").components(separatedBy: " - ")
        self.init(title: parts[0], detail: parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : nil)
    }
}
