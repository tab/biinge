import Foundation
import JellyfinAPI
@testable import Biinge

/// Canned Jellyfin responses for tests
final class MockJellyfinService: JellyfinService, @unchecked Sendable {
    var stream: PlaybackStream?
    var streamDelay: Duration = .zero
    var stopReportDelay: Duration = .zero
    /// The WebVTT each subtitle delivery URL returns
    var subtitleFiles: [String: String] = [:]
    /// The item each ID returns (a bare item with that ID otherwise)
    var items: [String: BaseItemDto] = [:]
    /// The episodes each "series item ID/season number" returns (none otherwise)
    var episodes: [String: [BaseItemDto]] = [:]
    /// Every report sent, in order, as "start", "progress" or "stop" with its position and pause state (a stop is never paused)
    private(set) var reports: [(kind: String, positionTicks: Int?, isPaused: Bool)] = []

    func page(of list: LibraryList, startIndex: Int, limit: Int) async throws -> LibraryPage {
        LibraryPage(items: [], total: 0)
    }

    func genres(of type: BaseItemKind) async throws -> [String] {
        []
    }

    func search(_ term: String, types: [BaseItemKind], startIndex: Int, limit: Int) async throws -> LibraryPage {
        LibraryPage(items: [], total: 0)
    }

    func episodes(seriesID: String, season: Int) async throws -> [BaseItemDto] {
        episodes["\(seriesID)/\(season)"] ?? []
    }

    func item(id: String) async throws -> BaseItemDto {
        items[id] ?? BaseItemDto(id: id)
    }

    func similar(itemID: String, limit: Int) async throws -> [BaseItemDto] {
        []
    }

    func nextUp(seriesID: String) async throws -> BaseItemDto? {
        nil
    }

    func playbackStream(itemID: String, audioIndex: Int?, subtitleIndex: Int?) async throws -> PlaybackStream {
        try await Task.sleep(for: streamDelay)
        guard let stream else { throw PlaybackError.noStream }
        // each request gets its own play session carrying the tracks it asked for
        return PlaybackStream(
            url: stream.url,
            itemID: stream.itemID,
            mediaSourceID: stream.mediaSourceID,
            playSessionID: "\(audioIndex ?? stream.audioIndex ?? 0)-\(subtitleIndex ?? stream.subtitleIndex ?? 0)",
            playMethod: stream.playMethod,
            audioIndex: audioIndex ?? stream.audioIndex,
            subtitleIndex: subtitleIndex ?? stream.subtitleIndex,
            audioStreams: stream.audioStreams,
            subtitleStreams: stream.subtitleStreams
        )
    }

    func subtitleFile(deliveryURL: String) async throws -> String {
        guard let file = subtitleFiles[deliveryURL] else { throw URLError(.fileDoesNotExist) }
        return file
    }

    func reportStart(_ state: PlaybackStateInfo) async throws {
        reports.append(("start", state.positionTicks, state.isPaused == true))
    }

    func reportProgress(_ state: PlaybackStateInfo) async throws {
        reports.append(("progress", state.positionTicks, state.isPaused == true))
    }

    func reportStopped(_ info: PlaybackStopInfo) async throws {
        try await Task.sleep(for: stopReportDelay)
        reports.append(("stop", info.positionTicks, false))
    }
}
