import Foundation
import Get
import JellyfinAPI

/// The library lists the apps browse
enum LibraryList: Sendable, Hashable {
    /// The movies grid in the given order and played state, narrowed to one genre when it names one
    case movies(LibrarySort, LibraryFilter, genre: String? = nil)
    /// The TV shows grid in the given order and played state, narrowed to one genre when it names one (Runtime keeps the title order)
    case series(LibrarySort, LibraryFilter, genre: String? = nil)
    /// Movies and series together, newest added first
    case recentlyAdded
    case collections, recentlyAddedMovies, recentlyAddedSeries, continueWatching, nextUp
    /// The items of one collection (the BoxSet item ID)
    case collection(String)
}

/// The orders of the Movies and TV Shows grids (Title ascending, the others largest or newest first)
enum LibrarySort: Sendable {
    case recentlyAdded, title, releaseYear, communityRating, runtime
}

/// The played states the Movies and TV Shows grids narrow to
enum LibraryFilter: Sendable {
    case all, unwatched, watched
}

/// One page of Jellyfin items and the list's total count
struct LibraryPage: Sendable {
    let items: [BaseItemDto]
    let total: Int
}

/// A stream AVPlayer can play and the IDs its reports need
struct PlaybackStream: Sendable {
    let url: URL
    let itemID: String
    let mediaSourceID: String
    let playSessionID: String?
    let playMethod: PlayMethod
    let audioIndex: Int?
    /// The text subtitle shown when the stream was requested; nil or -1 means off
    let subtitleIndex: Int?
    let audioStreams: [MediaStream]
    /// The text subtitles the app can draw, each with the delivery URL of its file
    let subtitleStreams: [MediaStream]
}

enum PlaybackError: LocalizedError {
    case noStream, notStarted

    var errorDescription: String? {
        switch self {
        case .noStream: "Jellyfin returned no playable stream."
        case .notStarted: "The stream didn't start. Check the server and try again."
        }
    }
}

/// The Jellyfin calls the apps make as the connected user (fronts the SDK so tests can use a mock)
protocol JellyfinService: Sendable {
    func page(of list: LibraryList, startIndex: Int, limit: Int) async throws -> LibraryPage
    /// The names of the genres the user's items of this type carry, in name order
    func genres(of type: BaseItemKind) async throws -> [String]
    /// The items of the given types whose names match the term
    func search(_ term: String, types: [BaseItemKind], startIndex: Int, limit: Int) async throws -> LibraryPage
    /// One season's episodes that have media, by the series' item ID and the season number, with their user data
    func episodes(seriesID: String, season: Int) async throws -> [BaseItemDto]
    /// One item with every field Jellyfin keeps for it (people, media streams and user data included)
    func item(id: String) async throws -> BaseItemDto
    /// The items in the user's libraries Jellyfin finds similar to the item
    func similar(itemID: String, limit: Int) async throws -> [BaseItemDto]
    /// The series' next episode to watch, nil when it has none
    func nextUp(seriesID: String) async throws -> BaseItemDto?
    /// A stream for the item with the chosen audio and text subtitle (nil leaves the choice to the server, -1 turns subtitles off)
    func playbackStream(itemID: String, audioIndex: Int?, subtitleIndex: Int?) async throws -> PlaybackStream
    /// A text subtitle's file as WebVTT, from its delivery URL
    func subtitleFile(deliveryURL: String) async throws -> String
    func reportStart(_ state: PlaybackStateInfo) async throws
    func reportProgress(_ state: PlaybackStateInfo) async throws
    func reportStopped(_ info: PlaybackStopInfo) async throws
}

/// The `JellyfinService` backed by the SDK client of the current connection
struct JellyfinAPIService: JellyfinService {
    let client: JellyfinClient
    let userID: String
    /// The connection whose reachability every call reports to (nil in tests that check only the requests)
    weak var connection: JellyfinConnection?
    /// The connection's generation when it made this service, so a call that ends after a disconnect reports nothing
    var generation = 0

    func page(of list: LibraryList, startIndex: Int, limit: Int) async throws -> LibraryPage {
        let result: BaseItemDtoQueryResult
        switch list {
        case .continueWatching:
            var parameters = Paths.GetResumeItemsParameters()
            parameters.userID = userID
            parameters.startIndex = startIndex
            parameters.limit = limit
            parameters.mediaTypes = [.video]
            parameters.fields = [.overview, .genres, .providerIDs]
            parameters.enableUserData = true
            result = try await reporting { try await client.send(Paths.getResumeItems(parameters: parameters)).value }
        case .nextUp:
            var parameters = Paths.GetNextUpParameters()
            parameters.userID = userID
            parameters.startIndex = startIndex
            parameters.limit = limit
            parameters.fields = [.overview, .genres, .providerIDs]
            parameters.enableUserData = true
            result = try await reporting { try await client.send(Paths.getNextUp(parameters: parameters)).value }
        case .movies, .series, .recentlyAdded, .collections, .recentlyAddedMovies, .recentlyAddedSeries, .collection:
            guard let parameters = Self.itemsParameters(for: list, userID: userID, startIndex: startIndex, limit: limit) else {
                preconditionFailure("itemsParameters covers every getItems list")
            }
            result = try await reporting { try await client.send(Paths.getItems(parameters: parameters)).value }
        }
        return LibraryPage(items: result.items ?? [], total: result.totalRecordCount ?? 0)
    }

    /// The `getItems` query for a list (nil for the lists with their own endpoint)
    static func itemsParameters(for list: LibraryList, userID: String, startIndex: Int, limit: Int) -> Paths.GetItemsParameters? {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.isRecursive = true
        parameters.startIndex = startIndex
        parameters.limit = limit
        switch list {
        case .movies(let sort, let filter, let genre), .series(let sort, let filter, let genre):
            let isMovies = if case .movies = list { true } else { false }
            parameters.includeItemTypes = isMovies ? [.movie] : [.series]
            // the name breaks ties in the year, rating and runtime orders so pages don't shift
            switch sort {
            case .recentlyAdded:
                parameters.sortBy = [.dateCreated]
                parameters.sortOrder = [.descending]
            case .title:
                parameters.sortBy = [.sortName]
            case .releaseYear:
                parameters.sortBy = [.productionYear, .sortName]
                parameters.sortOrder = [.descending, .ascending]
            case .communityRating:
                parameters.sortBy = [.communityRating, .sortName]
                parameters.sortOrder = [.descending, .ascending]
            case .runtime where isMovies:
                parameters.sortBy = [.runtime, .sortName]
                parameters.sortOrder = [.descending, .ascending]
            case .runtime:
                // TV shows offer no Runtime order, so they keep the title order
                parameters.sortBy = [.sortName]
            }
            switch filter {
            case .all:
                break
            case .unwatched:
                parameters.isPlayed = false
            case .watched:
                parameters.isPlayed = true
            }
            parameters.genres = genre.map { [$0] }
        case .recentlyAdded:
            parameters.includeItemTypes = [.movie, .series]
            parameters.sortBy = [.dateCreated]
            parameters.sortOrder = [.descending]
        case .collections:
            parameters.includeItemTypes = [.boxSet]
            parameters.sortBy = [.sortName]
        case .recentlyAddedMovies:
            parameters.includeItemTypes = [.movie]
            parameters.sortBy = [.dateCreated]
            parameters.sortOrder = [.descending]
        case .recentlyAddedSeries:
            parameters.includeItemTypes = [.series]
            parameters.sortBy = [.dateLastContentAdded]
            parameters.sortOrder = [.descending]
        case .collection(let id):
            // only the collection's direct children
            parameters.isRecursive = nil
            parameters.parentID = id
            parameters.sortBy = [.productionYear, .sortName]
        case .continueWatching, .nextUp:
            return nil
        }
        // Home's hero compares dates added, and its show and collection cards count seasons and titles
        parameters.fields = [.overview, .genres, .providerIDs, .dateCreated, .childCount]
        parameters.enableUserData = true
        return parameters
    }

    func genres(of type: BaseItemKind) async throws -> [String] {
        var parameters = Paths.GetGenresParameters()
        parameters.userID = userID
        parameters.includeItemTypes = [type]
        parameters.sortBy = [.sortName]
        parameters.enableImages = false
        let result = try await reporting { try await client.send(Paths.getGenres(parameters: parameters)).value }
        return result.items?.compactMap(\.name) ?? []
    }

    func search(_ term: String, types: [BaseItemKind], startIndex: Int, limit: Int) async throws -> LibraryPage {
        let parameters = Self.searchParameters(term: term, types: types, userID: userID, startIndex: startIndex, limit: limit)
        let result = try await reporting { try await client.send(Paths.getItems(parameters: parameters)).value }
        return LibraryPage(items: result.items ?? [], total: result.totalRecordCount ?? 0)
    }

    /// The `getItems` query for a search of the given types
    static func searchParameters(term: String, types: [BaseItemKind], userID: String, startIndex: Int, limit: Int) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.isRecursive = true
        parameters.searchTerm = term
        parameters.includeItemTypes = types
        parameters.startIndex = startIndex
        parameters.limit = limit
        // the Apple TV result cards mark new titles and count seasons
        parameters.fields = [.dateCreated, .childCount]
        parameters.enableUserData = true
        return parameters
    }

    func episodes(seriesID: String, season: Int) async throws -> [BaseItemDto] {
        var parameters = Paths.GetEpisodesParameters()
        parameters.userID = userID
        parameters.season = season
        parameters.isMissing = false
        parameters.enableUserData = true
        return try await reporting { try await client.send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).value }.items ?? []
    }

    func item(id: String) async throws -> BaseItemDto {
        try await reporting { try await client.send(Paths.getItem(itemID: id, userID: userID)).value }
    }

    func similar(itemID: String, limit: Int) async throws -> [BaseItemDto] {
        var parameters = Paths.GetSimilarItemsParameters()
        parameters.userID = userID
        parameters.limit = limit
        // the poster cards show seasons, the NEW badge and the series' provider IDs
        parameters.fields = [.providerIDs, .dateCreated, .childCount]
        return try await reporting { try await client.send(Paths.getSimilarItems(itemID: itemID, parameters: parameters)).value }.items ?? []
    }

    func nextUp(seriesID: String) async throws -> BaseItemDto? {
        var parameters = Paths.GetNextUpParameters()
        parameters.userID = userID
        parameters.seriesID = seriesID
        parameters.limit = 1
        parameters.fields = [.overview]
        parameters.enableUserData = true
        return try await reporting { try await client.send(Paths.getNextUp(parameters: parameters)).value }.items?.first
    }

    func playbackStream(itemID: String, audioIndex: Int?, subtitleIndex: Int?) async throws -> PlaybackStream {
        var parameters = Paths.GetPostedPlaybackInfoParameters()
        parameters.userID = userID
        // the server applies the chosen tracks only to a named media source; one-version items use the item ID
        parameters.mediaSourceID = itemID
        parameters.audioStreamIndex = audioIndex
        // the app draws subtitles, so a chosen one never reaches the server, which would burn it in
        parameters.subtitleStreamIndex = subtitleIndex == nil ? nil : -1
        parameters.maxStreamingBitrate = DeviceProfile.avPlayer.maxStreamingBitrate
        let request = Paths.getPostedPlaybackInfo(itemID: itemID, parameters: parameters, PlaybackInfoDto(deviceProfile: .avPlayer))
        let response = try await reporting { try await client.send(request).value }
        guard let source = response.mediaSources?.first, let sourceID = source.id else { throw PlaybackError.noStream }

        let url: URL?
        let playMethod: PlayMethod
        if let transcoding = source.transcodingURL {
            // the transcoding URL is server-relative, so it goes after the server address and its base path
            let server = client.configuration.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            url = URL(string: server + transcoding)
            playMethod = .transcode
        } else {
            var stream = Paths.GetVideoStreamParameters()
            stream.isStatic = true
            stream.mediaSourceID = sourceID
            stream.playSessionID = response.playSessionID
            url = client.url(with: Paths.getVideoStream(itemID: itemID, parameters: stream), queryAPIKey: true)
            playMethod = .directPlay
        }
        guard let url else { throw PlaybackError.noStream }

        let streams = source.mediaStreams ?? []
        let text = streams.filter { $0.type == .subtitle && $0.deliveryMethod == .external && $0.deliveryURL != nil }
        let shown: Int?
        if let subtitleIndex {
            shown = subtitleIndex
        } else if let index = Self.textDefault(source.defaultSubtitleStreamIndex, among: text) {
            shown = index
        } else if (source.defaultSubtitleStreamIndex ?? -1) >= 0 {
            // the server's default is a bitmap it burns in, so ask again without one
            return try await playbackStream(itemID: itemID, audioIndex: audioIndex, subtitleIndex: -1)
        } else {
            shown = -1
        }
        return PlaybackStream(
            url: url,
            itemID: itemID,
            mediaSourceID: sourceID,
            playSessionID: response.playSessionID,
            playMethod: playMethod,
            audioIndex: audioIndex ?? source.defaultAudioStreamIndex,
            subtitleIndex: shown,
            audioStreams: streams.filter { $0.type == .audio },
            subtitleStreams: text
        )
    }

    /// The server's default subtitle when the app can draw it, nil when it is off or a bitmap
    nonisolated static func textDefault(_ defaultIndex: Int?, among text: [MediaStream]) -> Int? {
        text.contains { $0.index == defaultIndex } ? defaultIndex : nil
    }

    func subtitleFile(deliveryURL: String) async throws -> String {
        // the delivery URL carries its own key; Stream.vtt asks the server to convert SRT, ASS and MP4 text alike
        let path = deliveryURL.replacingOccurrences(of: #"Stream\.\w+"#, with: "Stream.vtt", options: .regularExpression)
        let server = client.configuration.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: server + path) else { throw PlaybackError.noStream }
        var request = URLRequest(url: url)
        // the server extracts a subtitle from the whole file on its first request, which can take minutes
        request.timeoutInterval = 300
        let data = try await reporting {
            let (data, response) = try await URLSession.shared.data(for: request)
            // the status throws inside the report, so a proxy's 502, 503 or 504 counts as unreachable as the SDK's calls do
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw Get.APIError.unacceptableStatusCode(status) }
            return data
        }
        guard let file = String(bytes: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return file
    }

    func reportStart(_ state: PlaybackStateInfo) async throws {
        try await reporting { try await client.send(Paths.reportPlaybackStart(state)) }
    }

    func reportProgress(_ state: PlaybackStateInfo) async throws {
        try await reporting { try await client.send(Paths.reportPlaybackProgress(state)) }
    }

    func reportStopped(_ info: PlaybackStopInfo) async throws {
        try await reporting { try await client.send(Paths.reportPlaybackStopped(info)) }
    }

    /// Runs one call to the server and reports its outcome to the connection's reachability state
    @discardableResult
    private func reporting<T>(_ call: () async throws -> T) async throws -> T {
        do {
            let value = try await call()
            await connection?.record(nil, generation: generation)
            return value
        } catch {
            await connection?.record(error, generation: generation)
            throw error
        }
    }
}
