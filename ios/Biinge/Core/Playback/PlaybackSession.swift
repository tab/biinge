import AVFoundation
import Foundation
import JellyfinAPI
import Observation

/// Plays one Jellyfin item in AVPlayer, draws its text subtitles from their file, restarts the stream on an audio switch and drives its reports
@MainActor
@Observable
final class PlaybackSession {
    let player = AVPlayer()
    let title: String
    /// The item as the screen that started playback passed it (series name, numbers and runtime for the player's bars)
    let item: BaseItemDto
    /// Jellyfin's runtime in seconds, 0 when unknown
    let duration: Double
    private(set) var stream: PlaybackStream?
    private(set) var errorMessage: String?
    /// The text subtitle shown, nil or -1 for off (a pick swaps the cues and never restarts the stream)
    private(set) var subtitleIndex: Int?
    /// The subtitle line at the player's time, nil between lines and while the file loads
    private(set) var subtitleText: String?
    /// The text subtitle streams whose file failed to load, which the track list marks
    private(set) var failedSubtitles: Set<Int> = []
    /// The player's position in seconds, refreshed ten times a second
    private(set) var seconds: Double = 0
    /// Whether playback runs or waits to run (false only while paused or before the stream loads)
    private(set) var isPlaying = false
    /// Whether the player waits for the stream to buffer
    private(set) var isBuffering = false

    /// Where Try Again picks up: the last position shown, or the start position when nothing played yet
    var resumeTicks: Int {
        seconds > 0 ? Int(seconds * 10_000_000) : startTicks
    }

    private let service: any JellyfinService
    private let itemID: String
    private let reporter: PlaybackReporter
    private var timeObserver: Any?
    private var cueObserver: Any?
    private var cues: [SubtitleCue] = []
    private var cueLoad: Task<Void, Never>?
    private var startTicks = 0
    /// How long a new stream may take to become playable before the error shows
    private let startTimeout: Duration
    private var jumpObserver: (any NSObjectProtocol)?
    private var endObservers: [any NSObjectProtocol] = []
    /// The latest picked audio; audio switches run one at a time and each applies the latest pick
    private var pickedAudio: Int?
    private var switching: Task<Void, Never>?
    /// Set by stop, so a load still in flight never starts the player or a report afterwards
    private(set) var isStopped = false
    /// The first stop's report, which a repeat stop waits for
    private var stopReport: Task<Void, Never>?

    init(service: any JellyfinService, item: BaseItemDto, startTimeout: Duration = .seconds(30)) {
        self.service = service
        self.startTimeout = startTimeout
        itemID = item.id ?? ""
        title = item.name ?? ""
        self.item = item
        duration = Double(item.runTimeTicks ?? 0) / 10_000_000
        reporter = PlaybackReporter(service: service)
    }

    /// Starts from Jellyfin's stored position for the connected user
    func start(atTicks ticks: Int) async {
        startTicks = ticks
        guard let stream = await load(audioIndex: nil, subtitleIndex: nil, atTicks: ticks) else { return }
        pickedAudio = stream.audioIndex
        subtitleIndex = stream.subtitleIndex
        observe()
        loadCues()
        await reporter.started(stream, positionTicks: ticks, now: .now)
    }

    /// Restarts the stream with the audio track at the current position; the subtitle stays as it is
    func selectAudio(_ index: Int) async {
        pickedAudio = index
        let prior = switching
        let task = Task {
            await prior?.value
            await switchAudio()
        }
        switching = task
        await task.value
    }

    /// Shows a text subtitle stream, or turns subtitles off with nil, without touching the stream
    func selectSubtitle(_ index: Int?) {
        guard !isStopped else { return }
        subtitleIndex = index ?? -1
        loadCues()
    }

    /// Pauses at once, then reports the stop with the position Jellyfin keeps for resume (only the first call reports, a repeat waits for it)
    func stop() async {
        guard !isStopped else {
            await stopReport?.value
            return
        }
        isStopped = true
        let ticks = positionTicks
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let cueObserver { player.removeTimeObserver(cueObserver) }
        cueLoad?.cancel()
        if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver) }
        endObservers.forEach(NotificationCenter.default.removeObserver)
        timeObserver = nil
        cueObserver = nil
        jumpObserver = nil
        endObservers = []
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        isBuffering = false
        if let stream {
            let report = Task { await reporter.stopped(stream, positionTicks: ticks) }
            stopReport = report
            await report.value
        }
    }

    private var positionTicks: Int {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? Int(seconds * 10_000_000) : 0
    }

    private var isPaused: Bool {
        player.timeControlStatus == .paused
    }

    /// Restarts the stream with the picked audio; the switch replaces the play session, so the old one stops first
    private func switchAudio() async {
        guard let old = stream, !isStopped, pickedAudio != old.audioIndex else { return }
        let ticks = positionTicks
        guard let new = await load(audioIndex: pickedAudio, subtitleIndex: subtitleIndex ?? -1, atTicks: ticks) else { return }
        await reporter.stopped(old, positionTicks: ticks)
        // Close may have run during the stop report, and a stopped session never reports a stream started
        guard !isStopped else { return }
        await reporter.started(new, positionTicks: ticks, now: .now)
    }

    /// Fetches the shown subtitle's file and shows its cues at the player's time, or marks the track failed and turns subtitles off; a later pick or stop cancels it
    private func loadCues() {
        cueLoad?.cancel()
        cues = []
        subtitleText = nil
        guard let index = subtitleIndex, index >= 0,
              let path = stream?.subtitleStreams.first(where: { $0.index == index })?.deliveryURL else { return }
        cueLoad = Task {
            do {
                let file = try await service.subtitleFile(deliveryURL: path)
                guard !Task.isCancelled else { return }
                cues = SubtitleCue.parse(file)
                showCue()
            } catch {
                // a later pick or stop cancelled the load, which is no failure
                guard !Task.isCancelled else { return }
                // the track stays listed as failed, and the video plays on with subtitles off
                failedSubtitles.insert(index)
                subtitleIndex = -1
            }
        }
    }

    /// Sets the subtitle line, position and play state for the player's time, each only when it changes
    private func showCue() {
        let now = player.currentTime().seconds
        // the offset is the device's Subtitle Style timing, read each time so a change applies at once
        let text = SubtitleCue.text(at: now, in: cues, offset: UserDefaults.standard.double(forKey: SubtitleTiming.key))
        if text != subtitleText { subtitleText = text }
        if now.isFinite, now != seconds { seconds = now }
        let playing = player.timeControlStatus != .paused
        if playing != isPlaying { isPlaying = playing }
        let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if buffering != isBuffering { isBuffering = buffering }
    }

    /// Requests a stream, waits until AVPlayer can play it, seeks to the position and turns the stream's own captions off
    private func load(audioIndex: Int?, subtitleIndex: Int?, atTicks ticks: Int) async -> PlaybackStream? {
        do {
            let stream = try await service.playbackStream(itemID: itemID, audioIndex: audioIndex, subtitleIndex: subtitleIndex)
            guard !isStopped else { return nil }
            let item = AVPlayerItem(url: stream.url)
            player.replaceCurrentItem(with: item)
            // shortcut: polls the status, since its KVO async sequence never delivered the change; observe it if this shows up in profiles
            let deadline = ContinuousClock.now + startTimeout
            while item.status == .unknown, !isStopped, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard !isStopped else { return nil }
            guard item.status == .readyToPlay else {
                errorMessage = item.error?.localizedDescription ?? PlaybackError.notStarted.localizedDescription
                return nil
            }
            // Jellyfin's HLS stream always starts at zero, so the player seeks to the position itself
            await player.seek(to: CMTime(value: CMTimeValue(ticks), timescale: 10_000_000))
            // the app draws subtitles, so captions the stream itself carries stay off
            if let group = try await item.asset.loadMediaSelectionGroup(for: .legible) {
                item.select(nil, in: group)
            }
            // stop may have run during the waits above and already cleared the player
            guard !isStopped else { return nil }
            self.stream = stream
            errorMessage = nil
            player.play()
            return stream
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func observe() {
        cueObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showCue() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let stream = self.stream else { return }
                let ticks = self.positionTicks
                let isPaused = self.isPaused
                Task { await self.reporter.tick(stream, positionTicks: ticks, isPaused: isPaused, now: .now) }
            }
        }
        // the end of the item or a failure while playing ends the session like Close
        endObservers = [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let ended = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                let failed = notification.name == AVPlayerItem.failedToPlayToEndTimeNotification
                MainActor.assumeIsolated {
                    guard let self, let current = self.player.currentItem, ended == ObjectIdentifier(current) else { return }
                    if failed { self.errorMessage = "Playback stopped because the stream failed." }
                    Task { await self.stop() }
                }
            }
        }
        jumpObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.timeJumpedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // a Notification isn't Sendable, so only the jumped item's identity crosses into the main actor
            let jumped = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let stream = self.stream, let current = self.player.currentItem,
                      jumped == ObjectIdentifier(current) else { return }
                let ticks = self.positionTicks
                let isPaused = self.isPaused
                Task { await self.reporter.seeked(stream, positionTicks: ticks, isPaused: isPaused, now: .now) }
            }
        }
    }
}
