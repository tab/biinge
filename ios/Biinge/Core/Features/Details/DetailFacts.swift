import Foundation
import JellyfinAPI

/// One label and value of a details screen's facts block
struct DetailFact: Identifiable, Equatable {
    let label: String
    let value: String
    /// How many more there are than `value` names, as "+2" (apart so a row can truncate the name and keep this)
    var count: String?

    var id: String { label }
}

extension DetailFact {
    /// A fact, nil when it has no value to show
    private init?(_ label: String, _ value: String?) {
        guard let value, !value.isEmpty else { return nil }
        self.init(label: label, value: value)
    }

    /// A movie's facts (the tracks only while `play` can play the loaded `item`)
    static func movie(_ details: MovieDetails, item: BaseItemDto?, play: DetailsPlay, state: WatchState?, now: Date = .now) -> [DetailFact] {
        let streams = streams(of: item, play: play)
        // whole days in UTC, so a release today reads Released (ISO days sort as text)
        let upcoming = String(details.releaseDate?.prefix(10) ?? "") > now.formatted(.iso8601.year().month().day())
        return [
            DetailFact("Director", details.directors?.joined(separator: ", ")),
            DetailFact(upcoming ? "Releases" : "Released", day(details.releaseDate)),
            status(details.status),
            DetailFact("Audio", audio(streams)),
            subtitles(streams),
            DetailFact("List", listName(.movie, state: state)),
        ].compactMap { $0 }
    }

    /// A series' facts
    static func series(_ details: SeriesDetails, state: WatchState?, now: Date = .now) -> [DetailFact] {
        // whole days in UTC, so a first air today reads First aired (ISO days sort as text)
        let upcoming = String(details.releaseDate?.prefix(10) ?? "") > now.formatted(.iso8601.year().month().day())
        return [
            DetailFact("Created by", details.creators?.joined(separator: ", ")),
            DetailFact(upcoming ? "First airs" : "First aired", release(details.releaseDate, now: now)),
            status(details.status),
            DetailFact("List", listName(.series, state: state)),
        ].compactMap { $0 }
    }

    /// An episode's facts, with the series' `creators` when it lists no directors (the tracks only while `play` can play the loaded `item`)
    static func episode(_ details: EpisodeDetails, creators: [String]?, item: BaseItemDto?, play: DetailsPlay) -> [DetailFact] {
        let streams = streams(of: item, play: play)
        let directors = details.directors?.joined(separator: ", ") ?? ""
        return [
            directors.isEmpty ? DetailFact("Created by", creators?.joined(separator: ", ")) : DetailFact("Director", directors),
            DetailFact("Air date", day(details.airDate)),
            DetailFact("Audio", audio(streams)),
            subtitles(streams),
        ].compactMap { $0 }
    }

    /// A game's facts
    static func game(_ details: GameDetails, state: WatchState?, now: Date = .now) -> [DetailFact] {
        // whole days in UTC, so a release today reads Released (ISO days sort as text)
        let upcoming = String(details.releaseDate?.prefix(10) ?? "") > now.formatted(.iso8601.year().month().day())
        return [
            DetailFact("Developer", details.developers?.joined(separator: ", ")),
            DetailFact(upcoming ? "Releases" : "Released", day(details.releaseDate)),
            status(details.status),
            DetailFact("List", listName(.game, state: state)),
        ].compactMap { $0 }
    }

    /// The quality badges of the loaded `item` while `play` can play it (the resolution, then HDR, then ATMOS)
    static func badges(item: BaseItemDto?, play: DetailsPlay) -> [String] {
        let streams = streams(of: item, play: play)
        let video = streams.first { $0.type == .video }
        var badges: [String] = []
        // a scope encode shows its resolution in its width
        if (video?.height ?? 0) >= 2160 || (video?.width ?? 0) >= 3800 {
            badges.append("4K")
        } else if (video?.height ?? 0) >= 1080 || (video?.width ?? 0) >= 1900 {
            badges.append("1080p")
        }
        if let range = video?.videoRange, range != .sdr, range != .unknown { badges.append("HDR") }
        if streams.contains(where: { $0.type == .audio && isAtmos($0) }) { badges.append("ATMOS") }
        return badges
    }

    /// The streams of the loaded item when it is the one `play` can play, none otherwise
    private static func streams(of item: BaseItemDto?, play: DetailsPlay) -> [MediaStream] {
        guard case .play(let id) = play, item?.id == id else { return [] }
        return item?.mediaStreams ?? item?.mediaSources?.first?.mediaStreams ?? []
    }

    /// A date as "1 Mar 2024" (nil when it doesn't parse)
    private static func day(_ date: String?) -> String? {
        let parsed = date.flatMap { try? Date(String($0.prefix(10)), strategy: .iso8601.year().month().day()) }
        // the date holds no time, so it formats in UTC to keep its day
        return parsed?.formatted(.verbatim(
            "\(day: .defaultDigits) \(month: .abbreviated) \(year: .defaultDigits)",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt, calendar: Calendar(identifier: .gregorian)
        ))
    }

    /// A release as its day from six months before today on (the future too), its year before (nil when there is no date)
    static func release(_ date: String?, now: Date = .now) -> String? {
        guard let date, !date.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        // whole days in UTC, so a date exactly six months back stays recent at any time of day (ISO days sort as text)
        let cutoff = calendar.date(byAdding: .month, value: -6, to: calendar.startOfDay(for: now))?.formatted(.iso8601.year().month().day())
        if let cutoff, String(date.prefix(10)) >= cutoff, let full = day(date) { return full }
        return String(date.prefix(4))
    }

    /// The name of the track's language tag (nil when the tag is missing or unknown)
    private static func language(_ track: MediaStream) -> String? {
        track.language.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) }
    }

    /// Whether the audio track is Dolby Atmos
    private static func isAtmos(_ track: MediaStream) -> Bool {
        track.audioSpatialFormat == .dolbyAtmos || [track.profile, track.title].contains { $0?.localizedCaseInsensitiveContains("atmos") == true }
    }

    /// The default audio track, else the first, as "English · 5.1" or "English · Dolby Atmos"
    private static func audio(_ streams: [MediaStream]) -> String? {
        let tracks = streams.filter { $0.type == .audio }
        guard let track = tracks.first(where: { $0.isDefault == true }) ?? tracks.first else { return nil }
        // Jellyfin's "5.1(side)" names the speaker layout, which the fact leaves off
        let channels = track.channelLayout?.components(separatedBy: "(").first?.capitalized ?? ""
        // without a tag Jellyfin's title leads with a codec, so only the tag names the language
        return [language(track) ?? "", isAtmos(track) ? "Dolby Atmos" : channels].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The first subtitle language and the count of the others, as "English" and "+2" (a track with a missing or unknown tag goes by the first part of Jellyfin's title)
    private static func subtitles(_ streams: [MediaStream]) -> DetailFact? {
        var languages: [String] = []
        for stream in streams where stream.type == .subtitle {
            let name = language(stream) ?? TrackLabel(stream).title
            if !name.isEmpty && !languages.contains(name) { languages.append(name) }
        }
        guard let first = languages.first else { return nil }
        return DetailFact(label: "Subtitles", value: first, count: languages.count > 1 ? "+\(languages.count - 1)" : nil)
    }

    /// The release status as shown (nil on none and on "Released"; a production status gets a hyphen or a lowercase word)
    private static func status(_ status: String?) -> DetailFact? {
        switch status {
        case "Released": nil
        case "Canceled": DetailFact("Status", "Cancelled")
        case "Returning Series": DetailFact("Status", "Returning")
        case "Post Production": DetailFact("Status", "Post-production")
        case "In Production": DetailFact("Status", "In production")
        default: DetailFact("Status", status)
        }
    }

    /// The name of the kind's list holding the title, "Not tracked" on none
    private static func listName(_ kind: DetailKind, state: WatchState?) -> String {
        DetailList.lists(kind, server: "").first { $0.state == state }?.name ?? "Not tracked"
    }
}
