import AVFoundation
import Foundation
import JellyfinAPI
import Network
import Testing
@testable import Biinge

/// A local sound stands in for a stream, so these run without a server
private let sound = URL(fileURLWithPath: "/System/Library/Sounds/Submarine.aiff")

@MainActor
@Suite(.enabled(if: FileManager.default.fileExists(atPath: sound.path)))
struct PlaybackSessionTests {
    private let service = MockJellyfinService()

    init() {
        service.stream = PlaybackStream(
            url: sound,
            itemID: "item",
            mediaSourceID: "item",
            playSessionID: "s",
            playMethod: .directPlay,
            audioIndex: 1,
            subtitleIndex: nil,
            audioStreams: [],
            subtitleStreams: []
        )
        service.streamDelay = .milliseconds(300)
    }

    @Test func stopDuringTheFirstLoadLeavesNothingPlaying() async throws {
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))

        let starting = Task { await session.start(atTicks: 0) }
        try await Task.sleep(for: .milliseconds(100))
        await session.stop()
        await starting.value

        #expect(session.player.currentItem == nil)
        #expect(session.player.rate == 0)
        #expect(service.reports.isEmpty)
    }

    @Test func stopDuringATrackSwitchStopsTheSessionThatStarted() async throws {
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))
        await session.start(atTicks: 0)

        let switching = Task { await session.selectAudio(2) }
        try await Task.sleep(for: .milliseconds(100))
        await session.stop()
        await switching.value

        #expect(session.player.currentItem == nil)
        #expect(session.player.rate == 0)
        #expect(service.reports.first?.kind == "start")
        #expect(service.reports.last?.kind == "stop")
        #expect(service.reports.filter { $0.kind == "start" }.count == service.reports.filter { $0.kind == "stop" }.count)
    }

    @Test func playingToTheEndStopsTheSession() async throws {
        service.streamDelay = .zero
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))

        await session.start(atTicks: 0)
        // the sound lasts about a second; a busy simulator can take longer to post its end
        for _ in 0..<100 where service.reports.last?.kind != "stop" {
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(session.player.currentItem == nil)
        let kinds = service.reports.map(\.kind)
        #expect(kinds.first == "start")
        #expect(kinds.last == "stop")
        #expect(kinds.filter { $0 == "stop" }.count == 1)
    }

    @Test func closeDuringTheSwitchStopReportNeverStartsTheNewSession() async throws {
        service.streamDelay = .zero
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))
        await session.start(atTicks: 0)
        service.stopReportDelay = .milliseconds(500)

        let switching = Task { await session.selectAudio(2) }
        try await Task.sleep(for: .milliseconds(250))
        await session.stop()
        await switching.value

        #expect(service.reports.filter { $0.kind == "start" }.count == 1)
        #expect(session.player.currentItem == nil)
    }

    @Test func aRepeatStopWaitsForTheFirstStopsReport() async throws {
        service.streamDelay = .zero
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))
        await session.start(atTicks: 0)
        service.stopReportDelay = .milliseconds(500)

        // the end of the item stops the session, then the player's close stops it again
        let first = Task { await session.stop() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!service.reports.contains { $0.kind == "stop" })
        await session.stop()

        #expect(service.reports.filter { $0.kind == "stop" }.count == 1)
        await first.value
    }

    @Test func overlappingAudioPicksEndOnTheLatestAndKeepTheSubtitle() async throws {
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))
        await session.start(atTicks: 0)
        session.selectSubtitle(5)

        let first = Task { await session.selectAudio(3) }
        try await Task.sleep(for: .milliseconds(50))
        let second = Task { await session.selectAudio(2) }
        await first.value
        await second.value

        #expect(session.stream?.audioIndex == 2)
        #expect(session.stream?.subtitleIndex == 5)
        #expect(session.subtitleIndex == 5)
        let starts = service.reports.filter { $0.kind == "start" }.count
        let stops = service.reports.filter { $0.kind == "stop" }.count
        #expect(starts == stops + 1)
        await session.stop()
    }

    @Test func aSubtitlePickShowsItsCuesWithoutRestartingTheStream() async throws {
        service.streamDelay = .zero
        service.stream = streamWithSubtitles(shown: -1)
        service.subtitleFiles = ["/subs/3": "WEBVTT\n\n00:00.000 --> 00:10.000\nHello\n"]
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))
        await session.start(atTicks: 0)
        #expect(session.subtitleText == nil)
        let starts = service.reports.filter { $0.kind == "start" }.count

        session.selectSubtitle(3)
        for _ in 0..<100 where session.subtitleText == nil {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(session.subtitleText == "Hello")
        #expect(service.reports.filter { $0.kind == "start" }.count == starts)
        session.selectSubtitle(nil)
        #expect(session.subtitleText == nil)
        #expect(session.subtitleIndex == -1)
        await session.stop()
    }

    @Test func aSubtitleWhoseFileFailsIsMarkedAndTurnsSubtitlesOff() async throws {
        service.streamDelay = .zero
        service.stream = streamWithSubtitles(shown: -1)
        // no file for "/subs/3", so its load fails
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))
        await session.start(atTicks: 0)

        session.selectSubtitle(3)
        for _ in 0..<100 where session.failedSubtitles.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(session.failedSubtitles == [3])
        #expect(session.subtitleIndex == -1)
        #expect(session.subtitleText == nil)
        await session.stop()
    }

    @Test func theServersTextSubtitleShowsFromTheStart() async throws {
        service.streamDelay = .zero
        service.stream = streamWithSubtitles(shown: 3)
        service.subtitleFiles = ["/subs/3": "WEBVTT\n\n00:00.000 --> 00:10.000\nHello\n"]
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))

        await session.start(atTicks: 0)
        for _ in 0..<100 where session.subtitleText == nil {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(session.subtitleIndex == 3)
        #expect(session.subtitleText == "Hello")
        await session.stop()
    }

    @Test func aStreamThatNeverStartsSaysSo() async throws {
        let server = try await silentServer()
        defer { server.cancel() }
        service.streamDelay = .zero
        service.stream = try PlaybackStream(
            url: #require(URL(string: "http://127.0.0.1:\(server.port?.rawValue ?? 0)/master.m3u8")),
            itemID: "item",
            mediaSourceID: "item",
            playSessionID: "s",
            playMethod: .transcode,
            audioIndex: 1,
            subtitleIndex: nil,
            audioStreams: [],
            subtitleStreams: []
        )
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"), startTimeout: .milliseconds(500))

        await session.start(atTicks: 0)

        #expect(session.errorMessage == PlaybackError.notStarted.localizedDescription)
        #expect(service.reports.isEmpty)
        await session.stop()
    }

    @Test func tryAgainResumesFromTheLastPositionShown() async throws {
        service.streamDelay = .zero
        let session = PlaybackSession(service: service, item: BaseItemDto(id: "item"))

        await session.start(atTicks: 0)
        for _ in 0..<50 where session.seconds == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(session.seconds > 0)
        #expect(session.resumeTicks == Int(session.seconds * 10_000_000))
        await session.stop()
    }

    private func streamWithSubtitles(shown: Int) -> PlaybackStream {
        PlaybackStream(
            url: sound,
            itemID: "item",
            mediaSourceID: "item",
            playSessionID: "s",
            playMethod: .directPlay,
            audioIndex: 1,
            subtitleIndex: shown,
            audioStreams: [],
            subtitleStreams: [MediaStream(deliveryURL: "/subs/3", index: 3, language: "eng")]
        )
    }

    /// Accepts connections on loopback and never answers, like a server that can't produce the stream
    private func silentServer() async throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { $0.start(queue: .global()) }
        listener.start(queue: .global())
        for _ in 0..<100 where listener.port == nil || listener.port?.rawValue == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        return listener
    }
}

/// Try Again's position for a stream that never played, on every platform
@MainActor
struct PlaybackResumeTests {
    @Test func tryAgainBeforeAnythingPlayedResumesFromTheStartPosition() async {
        // no stream, so the start fails before the player shows a position
        let session = PlaybackSession(service: MockJellyfinService(), item: BaseItemDto(id: "item"))

        await session.start(atTicks: 42_000_000)

        #expect(session.errorMessage != nil)
        #expect(session.resumeTicks == 42_000_000)
    }
}

/// The WebVTT and SRT parsing behind the drawn subtitles, on every platform
struct SubtitleCueTests {
    @Test func parsesWebVTTWithSettingsMarkupAndShortStamps() {
        let file = "WEBVTT\n\nNOTE made by hand\n\n1\n00:01.500 --> 00:00:03.000 position:20% line:85%\n<i>Hello</i>\n{\\an8}there\n\n00:04.000 --> 00:05.000\n<font size=\"24\"> </font>\n"
        #expect(SubtitleCue.parse(file) == [SubtitleCue(start: 1.5, end: 3, text: "Hello\nthere")])
    }

    @Test func parsesSRTOutOfOrderWithCommasEntitiesAndWindowsLineEnds() {
        let file = "2\r\n01:00:00,000 --> 01:00:01,000\r\nLate &amp; loud\r\n\r\n1\r\n00:00:12,300 --> 00:00:15,470\r\nSecond\r\n"
        #expect(SubtitleCue.parse(file) == [
            SubtitleCue(start: 12.3, end: 15.47, text: "Second"),
            SubtitleCue(start: 3600, end: 3601, text: "Late & loud"),
        ])
    }

    @Test func theTimingOffsetMovesEveryCue() {
        let cues = [SubtitleCue(start: 1, end: 2, text: "A")]
        // later: the line shows 0.5 s after its own time
        #expect(SubtitleCue.text(at: 1.2, in: cues, offset: 0.5) == nil)
        #expect(SubtitleCue.text(at: 2.3, in: cues, offset: 0.5) == "A")
        // earlier: the line shows 0.5 s before it
        #expect(SubtitleCue.text(at: 0.6, in: cues, offset: -0.5) == "A")
        #expect(SubtitleCue.text(at: 1.6, in: cues, offset: -0.5) == nil)
    }

    @Test func showsTheCueOnlyInsideItsTimes() {
        let cues = [SubtitleCue(start: 1, end: 2, text: "A"), SubtitleCue(start: 1.5, end: 3, text: "B")]
        #expect(SubtitleCue.text(at: 0.99, in: cues) == nil)
        #expect(SubtitleCue.text(at: 1, in: cues) == "A")
        #expect(SubtitleCue.text(at: 1.7, in: cues) == "A\nB")
        #expect(SubtitleCue.text(at: 2, in: cues) == "B")
        #expect(SubtitleCue.text(at: 3, in: cues) == nil)
    }
}

/// The server's default subtitle the app may show at the start
struct TextDefaultTests {
    private let text = [MediaStream(index: 3), MediaStream(index: 4)]

    @Test func keepsATextDefault() {
        #expect(JellyfinAPIService.textDefault(4, among: text) == 4)
    }

    @Test func dropsABitmapOrMissingDefault() {
        #expect(JellyfinAPIService.textDefault(7, among: text) == nil)
        #expect(JellyfinAPIService.textDefault(-1, among: text) == nil)
        #expect(JellyfinAPIService.textDefault(nil, among: text) == nil)
    }
}

/// The player bars' visibility, times, badges and speed menu
struct PlayerChromeTests {
    private let input = Date(timeIntervalSince1970: 1000)

    @Test func barsHideOnlyAfterTheIdleTimeWhilePlaying() {
        #expect(PlayerChrome.isVisible(isPlaying: true, isLoading: false, isHeld: false, lastInput: input, now: input.addingTimeInterval(2.9)))
        #expect(!PlayerChrome.isVisible(isPlaying: true, isLoading: false, isHeld: false, lastInput: input, now: input.addingTimeInterval(3)))
    }

    @Test func barsStayWhilePausedLoadingOrHeld() {
        let later = input.addingTimeInterval(60)
        #expect(PlayerChrome.isVisible(isPlaying: false, isLoading: false, isHeld: false, lastInput: input, now: later))
        #expect(PlayerChrome.isVisible(isPlaying: true, isLoading: true, isHeld: false, lastInput: input, now: later))
        #expect(PlayerChrome.isVisible(isPlaying: true, isLoading: false, isHeld: true, lastInput: input, now: later))
    }

    @Test func clockReadsMinutesThenHours() {
        #expect(PlayerChrome.clock(0) == "0:00")
        #expect(PlayerChrome.clock(245.4) == "4:05")
        #expect(PlayerChrome.clock(245.6) == "4:06")
        #expect(PlayerChrome.clock(3725) == "1:02:05")
        #expect(PlayerChrome.clock(-3) == "0:00")
        #expect(PlayerChrome.clock(.nan) == "0:00")
    }

    @Test func badgesNameTheResolutionClassAndSurround() {
        #expect(PlayerChrome.badges(videoSize: CGSize(width: 3840, height: 1606), audioChannels: 6) == ["4K", "5.1"])
        #expect(PlayerChrome.badges(videoSize: CGSize(width: 1920, height: 804), audioChannels: 2) == ["1080p"])
        #expect(PlayerChrome.badges(videoSize: CGSize(width: 1280, height: 720), audioChannels: 8) == ["720p", "7.1"])
        // pillarboxed sources fall short in width
        #expect(PlayerChrome.badges(videoSize: CGSize(width: 2880, height: 2160), audioChannels: nil) == ["4K"])
        #expect(PlayerChrome.badges(videoSize: CGSize(width: 1440, height: 1080), audioChannels: nil) == ["1080p"])
        #expect(PlayerChrome.badges(videoSize: .zero, audioChannels: nil).isEmpty)
    }

    @Test func speedMenuRunsFromHalfToDouble() {
        #expect(PlayerChrome.speeds == [0.5, 0.75, 1, 1.25, 1.5, 2])
    }
}
