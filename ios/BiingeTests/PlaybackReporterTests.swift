import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

@MainActor
struct PlaybackReporterTests {
    private let service = MockJellyfinService()
    private let start = Date(timeIntervalSince1970: 1_000)

    private func stream(_ session: String) -> PlaybackStream {
        PlaybackStream(
            url: URL(fileURLWithPath: "/"),
            itemID: "item",
            mediaSourceID: "item",
            playSessionID: session,
            playMethod: .transcode,
            audioIndex: 1,
            subtitleIndex: nil,
            audioStreams: [],
            subtitleStreams: []
        )
    }

    private var kinds: [String] { service.reports.map(\.kind) }

    @Test func progressGoesOutEveryTenSeconds() async {
        let reporter = PlaybackReporter(service: service)
        await reporter.started(stream("a"), positionTicks: 0, now: start)

        for second in 1...25 {
            await reporter.tick(stream("a"), positionTicks: second, isPaused: false, now: start.addingTimeInterval(TimeInterval(second)))
        }

        #expect(kinds == ["start", "progress", "progress"])
        #expect(service.reports.map(\.positionTicks) == [0, 10, 20])
    }

    @Test func pauseAndResumeReportAtOnce() async {
        let reporter = PlaybackReporter(service: service)
        await reporter.started(stream("a"), positionTicks: 0, now: start)

        await reporter.tick(stream("a"), positionTicks: 1, isPaused: true, now: start.addingTimeInterval(1))
        await reporter.tick(stream("a"), positionTicks: 1, isPaused: true, now: start.addingTimeInterval(2))
        await reporter.tick(stream("a"), positionTicks: 1, isPaused: false, now: start.addingTimeInterval(3))

        #expect(kinds == ["start", "progress", "progress"])
        #expect(service.reports.map(\.isPaused) == [false, true, false])
    }

    @Test func seekReportsAtOnceAndRestartsTheInterval() async {
        let reporter = PlaybackReporter(service: service)
        await reporter.started(stream("a"), positionTicks: 0, now: start)

        await reporter.seeked(stream("a"), positionTicks: 600, isPaused: false, now: start.addingTimeInterval(2))
        await reporter.tick(stream("a"), positionTicks: 609, isPaused: false, now: start.addingTimeInterval(11))
        await reporter.tick(stream("a"), positionTicks: 610, isPaused: false, now: start.addingTimeInterval(12))

        #expect(kinds == ["start", "progress", "progress"])
        #expect(service.reports.map(\.positionTicks) == [0, 600, 610])
    }

    @Test func aTickOrSeekAfterStopSendsNothing() async {
        let reporter = PlaybackReporter(service: service)
        await reporter.started(stream("a"), positionTicks: 0, now: start)
        await reporter.stopped(stream("a"), positionTicks: 5)

        await reporter.tick(stream("a"), positionTicks: 30, isPaused: true, now: start.addingTimeInterval(30))
        await reporter.seeked(stream("a"), positionTicks: 40, isPaused: false, now: start.addingTimeInterval(31))

        #expect(kinds == ["start", "stop"])
    }

    @Test func stopReportsThePosition() async {
        let reporter = PlaybackReporter(service: service)
        await reporter.started(stream("a"), positionTicks: 0, now: start)

        await reporter.stopped(stream("a"), positionTicks: 1_234)

        #expect(kinds == ["start", "stop"])
        #expect(service.reports.last?.positionTicks == 1_234)
    }
}
