import Foundation
import JellyfinAPI

/// Sends the Jellyfin playback reports: start, progress every 10 seconds and at once on pause, seek and track switch, and stop
@MainActor
final class PlaybackReporter {
    static let interval: TimeInterval = 10

    private let service: any JellyfinService
    private var lastReport = Date.distantPast
    private var wasPaused = false
    /// Reports go out one at a time in the order they were made, so a progress report never lands after its stop
    private var sending: Task<Void, Never>?
    /// Play sessions already reported stopped; a late tick or seek for one sends nothing
    private var stoppedSessions: Set<String> = []

    init(service: any JellyfinService) {
        self.service = service
    }

    func started(_ stream: PlaybackStream, positionTicks: Int, now: Date) async {
        lastReport = now
        wasPaused = false
        let state = state(stream, positionTicks: positionTicks, isPaused: false)
        await send { [service] in try await service.reportStart(state) }
    }

    /// Called about once a second while playing; reports when the interval passed or playback paused or resumed
    func tick(_ stream: PlaybackStream, positionTicks: Int, isPaused: Bool, now: Date) async {
        guard !stoppedSessions.contains(Self.session(of: stream)),
              isPaused != wasPaused || now.timeIntervalSince(lastReport) >= Self.interval else { return }
        lastReport = now
        wasPaused = isPaused
        let state = state(stream, positionTicks: positionTicks, isPaused: isPaused)
        await send { [service] in try await service.reportProgress(state) }
    }

    func seeked(_ stream: PlaybackStream, positionTicks: Int, isPaused: Bool, now: Date) async {
        guard !stoppedSessions.contains(Self.session(of: stream)) else { return }
        lastReport = now
        wasPaused = isPaused
        let state = state(stream, positionTicks: positionTicks, isPaused: isPaused)
        await send { [service] in try await service.reportProgress(state) }
    }

    func stopped(_ stream: PlaybackStream, positionTicks: Int) async {
        let info = PlaybackStopInfo(
            itemID: stream.itemID,
            mediaSourceID: stream.mediaSourceID,
            playSessionID: stream.playSessionID,
            positionTicks: positionTicks
        )
        stoppedSessions.insert(Self.session(of: stream))
        await send { [service] in try await service.reportStopped(info) }
    }

    /// Queues one report behind the ones before it (reports are best effort, so a failure is dropped)
    private func send(_ report: @escaping @Sendable () async throws -> Void) async {
        let prior = sending
        let task = Task {
            await prior?.value
            _ = try? await report()
        }
        sending = task
        await task.value
    }

    private static func session(of stream: PlaybackStream) -> String {
        stream.playSessionID ?? stream.itemID
    }

    private func state(_ stream: PlaybackStream, positionTicks: Int, isPaused: Bool) -> PlaybackStateInfo {
        PlaybackStateInfo(
            audioStreamIndex: stream.audioIndex,
            canSeek: true,
            isPaused: isPaused,
            itemID: stream.itemID,
            mediaSourceID: stream.mediaSourceID,
            playMethod: stream.playMethod,
            playSessionID: stream.playSessionID,
            positionTicks: positionTicks,
            subtitleStreamIndex: stream.subtitleIndex
        )
    }
}
