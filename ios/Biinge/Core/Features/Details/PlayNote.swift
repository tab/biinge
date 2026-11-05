import Foundation

/// The note under a details screen's actions: why Play isn't here, where the series' next episode stands, or a Jellyfin play that Watched lacks (each platform renders it, with its own action for a kind that takes one)
struct PlayNote: Equatable {
    enum Kind: Equatable {
        /// This device has no Jellyfin connection
        case connect
        /// The library holds no single item for the title
        case notOnServer
        /// The server didn't answer the last call
        case unreachable
        /// Jellyfin marked the title played while biinge doesn't hold it watched
        case playedUnwatched
        /// The server lacks the season of the series' next episode
        case seasonNotOnServer
        /// The user is caught up, and the series' next episode has an air date
        case airs
    }

    let kind: Kind
    let text: String
    let systemImage: String
}

extension PlayNote {
    /// The note for what the title's Jellyfin item offers (nil for a play, unless Jellyfin played it while biinge doesn't hold it watched; `device` names this device in the connect note)
    init?(play: DetailsPlay, server: String?, playedUnwatched: Bool = false, device: String = DeviceInfo.deviceName) {
        let server = server ?? "server"
        switch play {
        case .connect:
            self.init(kind: .connect, text: "Jellyfin isn’t connected on this \(device), so Play isn’t available.", systemImage: "link")
        case .notOnServer:
            self.init(kind: .notOnServer, text: "Not on \(server). Add it to Jellyfin to play here.", systemImage: "server.rack")
        case .unreachable:
            self.init(kind: .unreachable, text: "Can’t reach \(server).", systemImage: "icloud.slash")
        case .play:
            // Jellyfin's played mark doesn't reach biinge's Watched by itself
            guard playedUnwatched else { return nil }
            self.init(kind: .playedUnwatched, text: "Played on \(server), not in your Watched list.", systemImage: "checkmark")
        }
    }

    /// The note that the server lacks the season of the series' next episode
    static func seasonNotOnServer(season: Int, episode: Int, server: String?) -> PlayNote {
        PlayNote(
            kind: .seasonNotOnServer,
            text: "You’re up to S\(season) · E\(episode). Season \(season) isn’t on \(server ?? "server").",
            systemImage: "server.rack"
        )
    }

    /// The note that the user is caught up until the episode airs (nil when `airDate` holds no day)
    static func airs(season: Int, episode: Int, airDate: String) -> PlayNote? {
        guard let day = try? Date(String(airDate.prefix(10)), strategy: .iso8601.year().month().day()) else { return nil }
        // the date holds no time, so it formats in UTC to keep its day
        let airs = day.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.wide).day().month(.abbreviated))
        return PlayNote(kind: .airs, text: "You’re caught up. S\(season) · E\(episode) airs \(airs).", systemImage: "calendar")
    }
}
