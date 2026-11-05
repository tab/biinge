import AVKit
import JellyfinAPI
import SwiftUI

/// Mac player: video, drawn subtitles, the `Biinge Mac Player` bars and the next-episode card, or the playback error with Try Again and Back
struct DesktopPlayerView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let session: PlaybackSession

    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsTracks = false
    @State private var showsStyle = false
    @State private var showsSpeed = false
    @State private var isScrubbing = false
    /// The speed menu's pick, which the next item keeps
    @State private var rate: Float = 1
    /// The last item's player, whose volume and mute the next item's player takes over
    @State private var previousPlayer: AVPlayer?
    /// The playing episode's neighbours (none until they load, and none for a movie)
    @State private var neighbors = EpisodeNeighbors()
    @State private var countdown = NextEpisodeCountdown()
    /// The measured control bar height, which the subtitle rises above
    @State private var barHeight: CGFloat = 176
    /// The measured height of the open panel, which the subtitle rises above
    @State private var panelHeight: CGFloat = 0

    /// How far the subtitle rises: above the open panel, above the bar while it shows, otherwise not at all
    private var subtitleLift: CGFloat {
        guard showsBars, card == nil else { return 0 }
        // 28 is the bar's bottom margin, 14 the gap above it and 12 the clearance above the topmost of them
        return showsTracks || showsSpeed ? 28 + barHeight + 14 + panelHeight + 12 : 28 + barHeight + 12
    }
    @State private var lastInput = Date.now
    @State private var now = Date.now
    /// The session that opened the player, nil until its first appearance (only its artwork grows; the next episode and Try Again show theirs filled)
    @State private var openedSession: ObjectIdentifier?
    /// Set while the opening play's artwork grows, so it fills the window for the whole Morph even when the stream is ready sooner
    @State private var isArtworkGrowing = true
    /// When the buffering spinner showed, nil while it hides
    @State private var bufferingShownAt: Date?

    private var showsBars: Bool {
        PlayerChrome.isVisible(
            isPlaying: session.isPlaying,
            isLoading: session.stream == nil || session.isBuffering,
            isHeld: showsTracks || showsSpeed || isScrubbing,
            lastInput: lastInput,
            now: now
        )
    }

    /// Whether the loading artwork grows into the player, which only the play that opened it does
    private var growsArtwork: Bool {
        openedSession == nil || openedSession == ObjectIdentifier(session)
    }

    /// The next episode while its card counts down in the credits, nil otherwise
    private var card: EpisodeNeighbors.Neighbor? {
        countdown.remaining == nil ? nil : neighbors.next
    }

    var body: some View {
        Group {
            if let errorMessage = session.errorMessage {
                failure(errorMessage)
            } else {
                player
            }
        }
        .background(.black)
        .onAppear { openedSession = ObjectIdentifier(session) }
        // the artwork's phase runs on its own clock, so Back and Escape still work at any point (Reduce Motion has no phase and crossfades)
        .task {
            if !reduceMotion { try? await Task.sleep(for: .seconds(MotionDuration.morph)) }
            isArtworkGrowing = false
        }
        // outside the error switch, so a failure keeps the window in fullscreen
        .background(PlaybackFullScreen())
        // the player view takes the keys itself while it is first responder; this covers focus anywhere else in the player
        .onExitCommand { escape() }
        // the end of the item stops the session itself, which closes the player; a failure stays on the error
        .onChange(of: session.isStopped) { _, isStopped in
            guard isStopped, session.errorMessage == nil, connection.playback === session else { return }
            // an episode that ends while its card counts down plays the next one at once
            if let card {
                play(card)
            } else {
                Task { await connection.stopPlayback() }
            }
        }
        // every item, the next episode's too, keeps the sound and speed and opens with its own neighbours and countdown and the panels closed
        .task(id: ObjectIdentifier(session)) {
            if let previousPlayer, previousPlayer !== session.player {
                session.player.volume = previousPlayer.volume
                session.player.isMuted = previousPlayer.isMuted
            }
            previousPlayer = session.player
            session.player.defaultRate = rate
            neighbors = EpisodeNeighbors()
            countdown = NextEpisodeCountdown()
            showsTracks = false
            showsSpeed = false
            guard let service = connection.service else { return }
            neighbors = await EpisodeNeighbors.load(session.item, service: service, apiClient: apiClient)
        }
        // the countdown follows the position, for an episode whose next one the server holds
        .onChange(of: session.seconds) {
            guard neighbors.next != nil else { return }
            countdown.update(position: session.seconds, duration: session.duration)
        }
        .task(id: countdown.remaining != nil) {
            while countdown.remaining != nil {
                try? await Task.sleep(for: .seconds(1))
                // Cancel, Play Now or leaving the credits ended the countdown during the second
                guard !Task.isCancelled else { return }
                // a playback error keeps its Try Again on screen instead of moving on
                if countdown.tick(), session.errorMessage == nil, let next = neighbors.next { play(next) }
            }
        }
        // a stall shows the spinner after 500 ms, and once shown it stays at least 500 ms (a stall that starts again meanwhile cancels the wait and keeps it)
        .task(id: session.isBuffering) {
            guard let wait = MotionDuration.stallWait(isBuffering: session.isBuffering, shownAt: bufferingShownAt, now: .now),
                  (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
            bufferingShownAt = session.isBuffering ? .now : nil
        }
    }

    private var player: some View {
        // the credits card shrinks the video to 42 % toward the leading side, where it keeps playing (Reduce Motion keeps it full size)
        let isShrunk = card != nil && !reduceMotion
        // the card slides in from the right as the video shrinks, and leaves faster (Reduce Motion fades it)
        let cardSlide: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 20))
        return ZStack {
            PlayerView(player: session.player, onKey: key, onClick: click)
                // a stall dims the picture a little under the spinner
                .overlay(Color.black.opacity(bufferingShownAt == nil ? 0 : 0.35).allowsHitTesting(false))
                // the radius and ring are drawn at full size, so they read 16 pt and 2 pt once shrunk
                .clipShape(RoundedRectangle(cornerRadius: isShrunk ? 16 / 0.42 : 0, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: isShrunk ? 16 / 0.42 : 0, style: .continuous)
                    .strokeBorder(.white.opacity(isShrunk ? 0.14 : 0), lineWidth: 2 / 0.42)
                    .allowsHitTesting(false))
                // the anchor leaves the shrunk video 5 % in from the leading edge and a quarter of the way down, as the board places it
                .scaleEffect(isShrunk ? 0.42 : 1, anchor: UnitPoint(x: 0.086, y: 0.428))
            // the poster grows into the window and holds it while the server prepares the stream, then the video fades in over it
            if session.stream == nil || isArtworkGrowing {
                PlayerArtwork(url: connection.posterURL(session.item, maxWidth: 300), grows: growsArtwork)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            // the subtitle rises above the bars and the open panel over Standard, snapping under Reduce Motion; an offset keeps its size, which follows the player's height.
            // While Subtitle Style is open, a sample stands in between lines so every change shows
            SubtitleOverlay(text: session.subtitleText ?? (showsTracks && showsStyle ? SubtitleOverlay.sample : nil))
                .offset(y: -subtitleLift)
                .animation(reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.standard), value: subtitleLift)
            if session.stream == nil {
                // a new stream can take a moment while the server prepares it
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("\(connection.serverName ?? "Jellyfin") is preparing the stream…")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.75))
                }
                .environment(\.colorScheme, .dark)
                // a new stream's loading state waits for the artwork to fill the window
                .entrance(after: growsArtwork ? MotionDuration.morph : 0)
            } else if bufferingShownAt != nil {
                // clicks reach the picture under it, and the bars stay usable
                ProgressView()
                    .controlSize(.large)
                    .environment(\.colorScheme, .dark)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if let card, let remaining = countdown.remaining {
                DesktopNextEpisodeCard(series: session.item.seriesName ?? "", next: card, remaining: remaining) {
                    play(card)
                } cancel: {
                    countdown.cancel()
                }
                .transition(.asymmetric(
                    insertion: cardSlide.animation(MotionCurve.standard.animation(MotionDuration.emphasis).delay(0.25)),
                    removal: cardSlide.animation(MotionCurve.exit.animation(MotionDuration.quick))
                ))
            } else if showsBars {
                // the bars arrive after the artwork fills the window, then show and hide with the pointer
                bars
                    .entrance(after: isArtworkGrowing && growsArtwork ? MotionDuration.morph : 0)
                    .transition(.opacity)
            }
        }
        .animation(MotionCurve.standard.animation(MotionDuration.standard), value: session.stream == nil || isArtworkGrowing)
        .animation(MotionCurve.standard.animation(MotionDuration.standard), value: showsBars)
        // the spinner and its dim fade in over Quick and leave over 150 ms on Exit
        .animation(bufferingShownAt == nil ? MotionCurve.exit.animation(MotionDuration.stallExit) : MotionCurve.standard.animation(MotionDuration.quick), value: bufferingShownAt == nil)
        // Cancel grows the video back from wherever the shrink has reached
        .animation(MotionCurve.standard.animation(MotionDuration.morph), value: card == nil)
        .onContinuousHover { _ in poke() }
        // re-reads the clock once the idle time after the last input has passed
        .task(id: lastInput) {
            try? await Task.sleep(for: .seconds(PlayerChrome.idle + 0.05))
            now = .now
        }
        .onChange(of: session.isPlaying) { poke() }
        // the panel reopens on the track list
        .onChange(of: showsTracks) { _, shows in
            if !shows { showsStyle = false }
        }
        .onChange(of: showsBars) { _, shows in
            if !shows { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }

    /// The top bar with Back, and the control bar with the Audio & Subtitles panel above its trailing end
    private var bars: some View {
        // the panels grow from 94 % out of the control that opened them over Quick and leave over the board's 150 ms Exit (Reduce Motion fades them)
        let popover: AnyTransition = reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)).combined(with: .offset(y: 6))
        let popoverTransition = AnyTransition.asymmetric(
            insertion: popover.animation(MotionCurve.standard.animation(MotionDuration.quick)),
            removal: popover.animation(MotionCurve.exit.animation(0.15))
        )
        return GeometryReader { proxy in
            ZStack {
                // the gradients pass clicks through to the video, which plays or pauses
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                GlassCircleButton(systemImage: "chevron.left", size: 22, label: "Back") { escapeToBack() }
                    .help("Back (Esc)")
                    .padding(.top, 18)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                VStack(alignment: .trailing, spacing: 14) {
                    if showsTracks, let stream = session.stream {
                        TracksPanel(session: session, stream: stream, showsStyle: $showsStyle)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                            .padding(.trailing, 40)
                            .transition(popoverTransition)
                    }
                    if showsSpeed {
                        SpeedPanel(rate: rate) { picked in
                            poke()
                            rate = picked
                            session.player.defaultRate = picked
                            if session.isPlaying { session.player.rate = picked }
                            showsSpeed = false
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                        .padding(.trailing, 70)
                        .transition(popoverTransition)
                    }
                    ControlBar(session: session, neighbors: neighbors, rate: rate, showsTracks: $showsTracks, showsSpeed: $showsSpeed,
                               isScrubbing: $isScrubbing, onInput: poke, playEpisode: play)
                        .frame(width: min(1120, proxy.size.width - 120))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
            }
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: showsTracks)
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: showsSpeed)
        }
        .foregroundStyle(Color(rgb: 0xF4F4F2))
        .environment(\.colorScheme, .dark)
    }

    /// Any pointer move, click or key shows the bars and restarts the idle time
    private func poke() {
        lastInput = .now
        now = lastInput
    }

    /// A click on the video closes the open panel, otherwise plays or pauses
    private func click() {
        poke()
        if showsTracks || showsSpeed {
            showsTracks = false
            showsSpeed = false
        } else {
            togglePlay()
        }
    }

    /// Space plays or pauses, the arrows skip 10 s, F toggles fullscreen and Escape steps back out of the panels, then out of the player (false passes the key on)
    private func key(_ code: UInt16) -> Bool {
        poke()
        switch code {
        case 49: togglePlay() // kVK_Space
        case 123: skip(by: -10) // kVK_LeftArrow
        case 124: skip(by: 10) // kVK_RightArrow
        case 3: NSApp.keyWindow?.toggleFullScreen(nil) // kVK_ANSI_F
        case 53: escape() // kVK_Escape
        default: return false
        }
        return true
    }

    private func escape() {
        if showsStyle {
            showsStyle = false
        } else if showsTracks || showsSpeed {
            showsTracks = false
            showsSpeed = false
        } else {
            escapeToBack()
        }
    }

    private func escapeToBack() {
        Task { await connection.stopPlayback() }
    }

    private func togglePlay() {
        if session.player.timeControlStatus == .paused {
            session.player.play()
        } else {
            session.player.pause()
        }
    }

    private func skip(by delta: Double) {
        let target = max(0, session.player.currentTime().seconds + delta)
        session.player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// Plays a neighbouring episode in this player, from the position Jellyfin holds for it, unless the player closed or moved on during the fetch (a failed fetch shows the shell's Can't play alert)
    private func play(_ neighbor: EpisodeNeighbors.Neighbor) {
        countdown.cancel()
        guard let id = neighbor.episode.jellyfinID else { return }
        let current = session
        attemptPlay {
            guard let service = connection.service else { return }
            let item = try await service.item(id: id)
            // Back or another play during the fetch replaced this session, so the next episode no longer belongs on screen
            guard connection.playback === current else { return }
            await connection.play(item)
        }
    }

    /// The playback error over the dark radial backdrop, with Try Again from the same position and Back
    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color(rgb: 0xE5484D))
                .frame(width: 68, height: 68)
                .background(Color(rgb: 0xE5484D).opacity(0.14), in: Circle())
            Text(session.item.type == .episode ? "This episode can’t be played" : "This movie can’t be played")
                .font(.system(size: 34, weight: .bold))
                .tracking(-1)
            Text(message)
                .font(.system(size: 17))
                .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    Task { await connection.play(session.item, atTicks: session.resumeTicks) }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(rgb: 0x101014))
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .background(Color(rgb: 0xF4F4F2), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .keyboardShortcut(.defaultAction)
                Button {
                    Task { await connection.stopPlayback() }
                } label: {
                    Text("Back")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .background(.white.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 10)
        }
        .foregroundStyle(Color(rgb: 0xF4F4F2))
        .frame(maxWidth: 560)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [Color(rgb: 0x17171D), .black],
                center: UnitPoint(x: 0.5, y: 0.45),
                startRadius: 0,
                endRadius: 700
            )
        )
    }
}

/// The glass control bar: title and badges, the scrubber with both times, then episodes and playback, volume, tracks, speed and fullscreen
private struct ControlBar: View {
    let session: PlaybackSession
    let neighbors: EpisodeNeighbors
    let rate: Float
    @Binding var showsTracks: Bool
    @Binding var showsSpeed: Bool
    /// Set while the scrubber is dragged, which keeps the bars up
    @Binding var isScrubbing: Bool
    let onInput: () -> Void
    let playEpisode: (EpisodeNeighbors.Neighbor) -> Void

    /// The scrubber's fraction while dragging, nil otherwise (gesture state, so a cancelled drag clears it too)
    @GestureState private var scrub: Double?
    /// The scrubber's fraction under the pointer, nil when it is elsewhere
    @State private var hover: Double?
    @State private var volume: Float = 1
    @State private var isMuted = false
    @State private var isFullScreen = false

    private var duration: Double {
        if session.duration > 0 { return session.duration }
        let seconds = session.player.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    private var position: Double {
        scrub.map { $0 * duration } ?? session.seconds
    }

    var body: some View {
        VStack(spacing: 14) {
            titleRow
            scrubberRow
            buttonRow
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .background(Color(rgb: 0x1E1E24).opacity(0.42), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.13)))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 20)
        .onAppear {
            volume = session.player.volume
            isMuted = session.player.isMuted
            isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in isFullScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in isFullScreen = false }
    }

    /// Series or year above the episode code and title, with the quality badges trailing
    private var titleRow: some View {
        let item = session.item
        let isEpisode = item.type == .episode
        let above = isEpisode ? item.seriesName : item.productionYear.map(String.init)
        let title = isEpisode ? "\(episodeCode(item)) · \(session.title)" : session.title
        let audio = session.stream?.audioStreams.first { $0.index == session.stream?.audioIndex }
        let badges = PlayerChrome.badges(videoSize: session.player.currentItem?.presentationSize ?? .zero, audioChannels: audio?.channels)
        return HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                if let above {
                    Text(above)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.65))
                }
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.system(size: 11.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.8))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(rgb: 0xF4F4F2).opacity(0.4), lineWidth: 1.5))
                }
            }
        }
        .padding(.horizontal, 4)
    }

    /// The elapsed time, the scrubber with its hover time, and the time left
    private var scrubberRow: some View {
        HStack(spacing: 14) {
            Text(PlayerChrome.clock(position))
                .frame(width: 56, alignment: .leading)
            GeometryReader { proxy in
                let fraction = duration > 0 ? min(1, max(0, position / duration)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2)).frame(height: 6)
                    Capsule().fill(Color(rgb: 0xF4F4F2)).frame(width: proxy.size.width * fraction, height: 6)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .offset(x: proxy.size.width * fraction - 8)
                    if let hover, scrub == nil {
                        Text(PlayerChrome.clock(hover * duration))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                            .fixedSize()
                            .position(x: proxy.size.width * hover, y: -18)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let point) = phase {
                        hover = min(1, max(0, point.x / proxy.size.width))
                    } else {
                        hover = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($scrub) { drag, scrub, _ in
                            scrub = min(1, max(0, drag.location.x / proxy.size.width))
                        }
                        .onChanged { _ in onInput() }
                        .onEnded { drag in
                            let fraction = min(1, max(0, drag.location.x / proxy.size.width))
                            if duration > 0 {
                                session.player.seek(to: CMTime(seconds: fraction * duration, preferredTimescale: 600))
                            }
                            onInput()
                        }
                )
                .onChange(of: scrub != nil) { _, dragging in isScrubbing = dragging }
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue(PlayerChrome.clock(position))
                .accessibilityAdjustableAction { direction in
                    let delta: Double = direction == .increment ? 10 : -10
                    session.player.seek(to: CMTime(seconds: max(0, session.seconds + delta), preferredTimescale: 600))
                }
            }
            .frame(height: 22)
            Text("-" + PlayerChrome.clock(max(0, duration - position)))
                .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.75))
                .frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 14, weight: .medium).monospacedDigit())
        .padding(.horizontal, 4)
    }

    /// Previous episode, back 10, play or pause, forward 10 and next episode leading; volume, Audio & Subtitles, speed and fullscreen trailing
    private var buttonRow: some View {
        HStack {
            HStack(spacing: 6) {
                BarButton(systemImage: "backward.end.fill", size: 20, label: "Previous episode") {
                    onInput()
                    if let previous = neighbors.previous { playEpisode(previous) }
                }
                .disabled(neighbors.previous == nil)
                .help("Previous episode")
                BarButton(systemImage: "gobackward.10", size: 22, label: "Back 10 seconds") { skip(by: -10) }
                    .help("Back 10 seconds (←)")
                BarButton(systemImage: session.isPlaying ? "pause.fill" : "play.fill", size: 30, diameter: 52,
                          label: session.isPlaying ? "Pause" : "Play") {
                    onInput()
                    if session.isPlaying { session.player.pause() } else { session.player.play() }
                }
                .help("Play/Pause (Space)")
                BarButton(systemImage: "goforward.10", size: 22, label: "Forward 10 seconds") { skip(by: 10) }
                    .help("Forward 10 seconds (→)")
                BarButton(systemImage: "forward.end.fill", size: 20, label: "Next episode") {
                    onInput()
                    if let next = neighbors.next { playEpisode(next) }
                }
                .disabled(neighbors.next == nil)
                .help("Next episode")
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        onInput()
                        isMuted.toggle()
                        session.player.isMuted = isMuted
                    } label: {
                        Image(systemName: isMuted || volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 17))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                    Slider(value: Binding(get: { Double(volume) }, set: { value in
                        onInput()
                        volume = Float(value)
                        session.player.volume = volume
                        if isMuted, value > 0 {
                            isMuted = false
                            session.player.isMuted = false
                        }
                    }), in: 0...1)
                    .controlSize(.small)
                    .tint(Color(rgb: 0xF4F4F2))
                    .frame(width: 96)
                    .accessibilityLabel("Volume")
                }
                .padding(.leading, 6)
                .padding(.trailing, 10)
                BarButton(systemImage: showsTracks ? "captions.bubble.fill" : "captions.bubble", size: 20, label: "Audio & Subtitles",
                          isActive: showsTracks) {
                    onInput()
                    showsSpeed = false
                    showsTracks.toggle()
                }
                .help("Audio & Subtitles")
                Button {
                    onInput()
                    showsTracks = false
                    showsSpeed.toggle()
                } label: {
                    Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "×")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .frame(minWidth: 48, minHeight: 42)
                        .padding(.horizontal, 8)
                        .background(.white.opacity(showsSpeed ? 0.16 : 0), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(BarHoverStyle(shape: Capsule()))
                .help("Playback speed")
                .accessibilityLabel("Playback speed")
                .accessibilityValue(rate.formatted() + "×")
                BarButton(systemImage: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                          size: 18, label: isFullScreen ? "Exit Full Screen" : "Full Screen") {
                    onInput()
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .help("Full Screen (F)")
            }
        }
    }

    private func skip(by delta: Double) {
        onInput()
        let target = max(0, session.player.currentTime().seconds + delta)
        session.player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }
}

/// A round icon button of the control bar with a hover fill, filled while its panel is open
private struct BarButton: View {
    let systemImage: String
    let size: CGFloat
    var diameter: CGFloat = 42
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(width: diameter, height: diameter)
                .background(.white.opacity(isActive ? 0.16 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(BarHoverStyle(shape: Circle()))
        .accessibilityLabel(label)
    }
}

/// The player bar's hover fill and press scale, dimmed while disabled (Reduce Motion brightens the fill on press in place of the scale)
struct BarHoverStyle<S: Shape>: ButtonStyle {
    let shape: S
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.3)
            .background(.white.opacity(isHovered && isEnabled ? (configuration.isPressed && reduceMotion ? 0.2 : 0.1) : 0), in: shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(MotionCurve.standard.animation(MotionDuration.press), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// The round glass button of the top bar
private struct GlassCircleButton: View {
    let systemImage: String
    let size: CGFloat
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.75, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .background(Color(rgb: isHovered ? 0x3C3C44 : 0x24242A).opacity(isHovered ? 0.55 : 0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
    }
}

/// The Audio & Subtitles panel above the control bar: audio tracks beside Off and the text subtitles with Subtitle Style below, or the Subtitle Style page
private struct TracksPanel: View {
    let session: PlaybackSession
    let stream: PlaybackStream
    @Binding var showsStyle: Bool

    @AppStorage(SubtitleSize.key) private var size = SubtitleSize.medium
    @AppStorage(SubtitleBackground.key) private var background = SubtitleBackground.shadow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The shown page's height, which the panel follows as the pages slide (nil until the first page measures)
    @State private var pageHeight: CGFloat?

    var body: some View {
        // the pages slide 24 pt apart as they cross over Standard, the tracks to the leading side (Reduce Motion crossfades them)
        ZStack(alignment: .top) {
            if showsStyle {
                DesktopSubtitleStylePage(isOff: (session.subtitleIndex ?? -1) < 0) { showsStyle = false }
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
                    .transition((reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(x: 24)))
                        .animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else {
                VStack(spacing: 0) {
                    tracks
                    HStack {
                        Spacer()
                        Button { showsStyle = true } label: {
                            HStack(spacing: 8) {
                                Text("Subtitle Style")
                                    .fontWeight(.semibold)
                                Text("\(size.label) · \(background.label)")
                                    .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.5))
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.6))
                            }
                            .font(.system(size: 14))
                            .padding(.leading, 14)
                            .padding(.trailing, 8)
                            .frame(height: 34)
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(BarHoverStyle(shape: RoundedRectangle(cornerRadius: 10)))
                    }
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 2))
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
                    .padding(.top, 6)
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
                .transition((reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(x: -24)))
                    .animation(MotionCurve.standard.animation(MotionDuration.standard)))
            }
        }
        // the panel resizes to the new page as they slide, and snaps under Reduce Motion
        .frame(height: pageHeight, alignment: .top)
        .animation(reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.standard), value: pageHeight)
        .padding(10)
        .frame(width: 560)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glassPanel()
    }

    /// Audio tracks beside Off and the text subtitles, a checkmark on each pick
    private var tracks: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                header("Audio")
                ForEach(stream.audioStreams, id: \.index) { track in
                    if let index = track.index {
                        TrackRow(track: track, isSelected: index == stream.audioIndex) {
                            Task { await session.selectAudio(index) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                header("Subtitles")
                // an index of -1 or none is Off
                TrackRow(title: "Off", detail: nil, isSelected: (session.subtitleIndex ?? -1) < 0) {
                    session.selectSubtitle(nil)
                }
                ForEach(stream.subtitleStreams, id: \.index) { track in
                    if let index = track.index {
                        TrackRow(track: track, isSelected: index == session.subtitleIndex, isFailed: session.failedSubtitles.contains(index)) {
                            session.selectSubtitle(index)
                        }
                    }
                }
            }
            .padding(.leading, 6)
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.5))
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 6, trailing: 12))
    }
}

/// The speed menu above the control bar: each rate with a checkmark on the current one
private struct SpeedPanel: View {
    let rate: Float
    let pick: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Speed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.5))
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            ForEach(PlayerChrome.speeds, id: \.self) { speed in
                let label = speed.formatted(.number.precision(.fractionLength(0...2))) + "×"
                TrackRow(title: speed == 1 ? label + " (Normal)" : label, detail: nil, isSelected: speed == rate) { pick(speed) }
            }
        }
        .padding(6)
        .frame(width: 190)
        .glassPanel()
    }
}

/// One row in a panel: a checkmark slot, the language, and the rest of Jellyfin's title below it, with a hover highlight (a track whose file failed says so and can't be picked)
private struct TrackRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let isFailed: Bool
    let select: () -> Void

    @State private var isHovered = false

    init(track: MediaStream, isSelected: Bool, isFailed: Bool = false, select: @escaping () -> Void) {
        let label = TrackLabel(track)
        self.init(title: label.title, detail: label.detail, isSelected: isSelected, isFailed: isFailed, select: select)
    }

    init(title: String, detail: String?, isSelected: Bool, isFailed: Bool = false, select: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.isFailed = isFailed
        self.select = select
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .opacity(isSelected ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                    if isFailed {
                        Text("Couldn’t load from the server")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(rgb: 0xFF8A8D))
                    } else if let detail {
                        Text(detail)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.5))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .opacity(isFailed ? 0.6 : 1)
            .background(.white.opacity(isHovered && !isFailed ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isFailed)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// AVPlayerView on the session's player with its own controls off, since the bars above it are ours
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    let onKey: (UInt16) -> Bool
    let onClick: () -> Void

    func makeNSView(context: Context) -> KeyPlayerView {
        let view = KeyPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.onKey = onKey
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: KeyPlayerView, context: Context) {
        // the next episode or Try Again brings a new session's player into the same view
        if view.player !== player { view.player = player }
        view.onKey = onKey
        view.onClick = onClick
    }
}

/// AVPlayerView that takes first responder on joining a window and hands its keys and clicks to the bars
private final class KeyPlayerView: AVPlayerView {
    var onKey: (UInt16) -> Bool = { _ in false }
    var onClick: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if !onKey(event.keyCode) {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}

private extension View {
    /// The tinted glass behind the player's panels
    func glassPanel() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(Color(rgb: 0x222228).opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.13)))
            .shadow(color: .black.opacity(0.5), radius: 35, y: 24)
    }
}
