import AVFoundation
import JellyfinAPI
import SwiftUI

extension View {
    /// Shows the player in a window of its own above the tabs and every open sheet while connection.playback is set
    func presentsPlayer(connection: JellyfinConnection, apiClient: APIClient) -> some View {
        modifier(PlayerPresenter(connection: connection, apiClient: apiClient))
    }
}

/// Holds the player's window, which sits above the main window so no sheet or alert there can block or cover the player
private struct PlayerPresenter: ViewModifier {
    let connection: JellyfinConnection
    let apiClient: APIClient

    @State private var window: UIWindow?
    /// The window that was key before the player, which takes the keyboard back on close
    @State private var previousKey: UIWindow?

    func body(content: Content) -> some View {
        content
            .onChange(of: connection.playback == nil) { _, isClosed in
                if isClosed { dismiss() } else { present() }
            }
            // a sign-out while playing removes the shell, and the player goes with it
            .onDisappear { dismiss() }
    }

    private func present() {
        guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        // a video player plays with the ring switch on silent
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        AppDelegate.allowsLandscape = true
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.overrideUserInterfaceStyle = .dark
        let host = UIHostingController(rootView: PlayerWindowRoot(connection: connection, apiClient: apiClient))
        host.view.backgroundColor = .black
        // VoiceOver stays in the player instead of reaching the tabs and sheets beneath it
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        previousKey = scene.keyWindow
        window.alpha = 0
        window.makeKeyAndVisible()
        UIView.animate(withDuration: MotionDuration.quick) { window.alpha = 1 }
        // a phone held sideways turns the player at once
        host.setNeedsUpdateOfSupportedInterfaceOrientations()
        self.window = window
    }

    private func dismiss() {
        guard let window else { return }
        self.window = nil
        window.isHidden = true
        AppDelegate.allowsLandscape = false
        // the tabs stay portrait, so the phone turns back once the player goes
        guard let scene = window.windowScene else { return }
        // the main window takes the keyboard back, so a field in an open sheet keeps working
        (previousKey ?? scene.windows.first { $0 !== window })?.makeKeyAndVisible()
        previousKey = nil
        // a podcast or music app the video interrupted gets its resume notice
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }
}

/// The player window's content: the playing session's player, with its own Can't play alert since the main window's sits below it
private struct PlayerWindowRoot: View {
    let connection: JellyfinConnection
    let apiClient: APIClient

    var body: some View {
        Group {
            if let session = connection.playback {
                MobilePlayerView(connection: connection, apiClient: apiClient, session: session)
            }
        }
        .playFailureAlert(connection: connection)
    }
}

/// The player's open panel
enum PlayerPanel {
    case tracks, style, speed
}

/// iPhone player: video, drawn subtitles, the `Biinge iOS Player` controls, panels and next-episode card, or the starting state and the playback error with Try Again and Back
struct MobilePlayerView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let session: PlaybackSession

    /// The player's text colour
    static let text = Color(rgb: 0xF4F4F2)

    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var panel: PlayerPanel?
    @State private var isScrubbing = false
    /// The speed menu's pick, which the next item keeps
    @State private var rate: Float = 1
    /// The playing episode's neighbours (none until they load, and none for a movie)
    @State private var neighbors = EpisodeNeighbors()
    @State private var countdown = NextEpisodeCountdown()
    @State private var lastInput = Date.now
    @State private var now = Date.now
    /// The session that opened the player, nil until its first appearance (only its artwork grows; the next episode and Try Again show theirs filled)
    @State private var openedSession: ObjectIdentifier?
    /// Set while the opening play's artwork grows, so the player waits for the whole Morph even when the stream is ready sooner
    @State private var isArtworkGrowing = true
    /// When the buffering spinner showed, nil while it hides
    @State private var bufferingShownAt: Date?

    private var showsBars: Bool {
        PlayerChrome.isVisible(
            isPlaying: session.isPlaying,
            isLoading: session.stream == nil || session.isBuffering,
            // VoiceOver needs the controls to stay where it found them
            isHeld: panel != nil || isScrubbing || voiceOver,
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
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { proxy in
                if let errorMessage = session.errorMessage {
                    PlayerFailure(connection: connection, session: session, message: errorMessage, isLandscape: proxy.size.width > proxy.size.height)
                } else if session.stream == nil || isArtworkGrowing {
                    PlayerStarting(connection: connection, session: session, size: proxy.size, insets: insets, growsArtwork: growsArtwork)
                        .transition(.opacity)
                } else {
                    // the video and its controls fade in over the artwork once the stream is ready
                    player(size: proxy.size, insets: insets)
                        .transition(.opacity)
                }
            }
            .animation(MotionCurve.standard.animation(MotionDuration.standard), value: session.stream == nil || isArtworkGrowing)
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(Self.text)
        .onAppear { openedSession = ObjectIdentifier(session) }
        // the artwork's phase runs on its own clock, so Close still works at any point (Reduce Motion has no phase and crossfades)
        .task {
            if !reduceMotion { try? await Task.sleep(for: .seconds(MotionDuration.morph)) }
            isArtworkGrowing = false
        }
        .environment(\.colorScheme, .dark)
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
        // every item, the next episode's too, keeps the speed and opens with its own neighbours and countdown and the panels closed
        .task(id: ObjectIdentifier(session)) {
            session.player.defaultRate = rate
            neighbors = EpisodeNeighbors()
            countdown = NextEpisodeCountdown()
            panel = nil
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

    private func player(size: CGSize, insets: EdgeInsets) -> some View {
        let isLandscape = size.width > size.height
        let isSidePanel = panel == .tracks || panel == .style
        let showsControls = showsBars && card == nil && !(isLandscape && isSidePanel)
        // the next-episode card shrinks the video to a still at the top in portrait and the leading edge in landscape
        let video = if card == nil {
            CGRect(origin: .zero, size: size)
        } else if isLandscape {
            CGRect(x: insets.leading + 2, y: 64, width: 320, height: 180)
        } else {
            CGRect(x: 20, y: 120, width: size.width - 40, height: (size.width - 40) * 9 / 16)
        }
        let panelSize = if isLandscape {
            CGSize(width: min(panel == .style ? 420 : 520, size.width - insets.leading - insets.trailing), height: size.height - 20)
        } else {
            CGSize(width: size.width, height: size.height * (panel == .style ? 0.47 : 0.65))
        }
        return ZStack(alignment: .topLeading) {
            VideoLayer(player: session.player)
                .frame(width: video.width, height: video.height)
                // a stall dims the picture a little under the spinner
                .overlay(Color.black.opacity(bufferingShownAt == nil ? 0 : 0.35))
                .clipShape(RoundedRectangle(cornerRadius: card == nil ? 0 : 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(card == nil ? 0 : 0.14))
                }
                .offset(x: video.minX, y: video.minY)
                .accessibilityHidden(true)
            // a tap shows or hides the controls, or closes the speed menu
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { tap(showsControls: showsControls) }
                .accessibilityHidden(true)
            if showsControls {
                controls(size: size, insets: insets, isLandscape: isLandscape)
                    .transition(.opacity)
            }
            if bufferingShownAt != nil {
                // over the picture's centre and above the controls, so the play button it covers keeps working
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(width: video.width, height: video.height)
                    .offset(x: video.minX, y: video.minY)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Loading")
                    .transition(.opacity)
            }
            if isSidePanel {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { panel = nil }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
            subtitles(size: size, isLandscape: isLandscape, isSidePanel: isSidePanel, panelSize: panelSize, showsControls: showsControls)
            if isSidePanel, let stream = session.stream {
                PlayerTracksPanel(session: session, stream: stream, isLandscape: isLandscape, bottomInset: insets.bottom, panel: $panel)
                    .frame(width: panelSize.width, height: panelSize.height)
                    // the panel resizes to the Subtitle Style page over Standard as the pages slide, and snaps under Reduce Motion
                    .animation(reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.standard), value: panel == .style)
                    .padding(.top, isLandscape ? 10 : 0)
                    .padding(.trailing, isLandscape ? insets.trailing : 0)
                    .frame(width: size.width, height: size.height, alignment: isLandscape ? .topTrailing : .bottom)
                    .transition(reduceMotion ? .opacity : .move(edge: isLandscape ? .trailing : .bottom))
            }
            if panel == .speed {
                PlayerSpeedMenu(rate: rate) { picked in
                    poke()
                    rate = picked
                    session.player.defaultRate = picked
                    if session.isPlaying { session.player.rate = picked }
                    panel = nil
                }
                // above the speed pill, which sits 44 points tall on the bottom row
                .padding(.leading, isLandscape ? max(insets.leading, insets.trailing) + 2 : 20)
                .padding(.bottom, (isLandscape ? 14 : insets.bottom + 18) + 48)
                .frame(width: size.width, height: size.height, alignment: .bottomLeading)
                .transition(.opacity)
            }
            if let card, let remaining = countdown.remaining {
                PlayerNextEpisodeCard(next: card, remaining: remaining, isLandscape: isLandscape) {
                    play(card)
                } cancel: {
                    countdown.cancel()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(EdgeInsets(
                    top: isLandscape ? video.minY : video.maxY + 33,
                    leading: isLandscape ? video.maxX + 28 : 20,
                    bottom: 0,
                    trailing: isLandscape ? max(insets.trailing, 20) : 20
                ))
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        // the video shrinks for the card over Morph, as on Mac and Apple TV
        .animation(reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.morph), value: card == nil)
        .animation(MotionCurve.standard.animation(MotionDuration.standard), value: showsControls)
        // the spinner and its dim fade in over Quick and leave over 150 ms on Exit
        .animation(bufferingShownAt == nil ? MotionCurve.exit.animation(MotionDuration.stallExit) : MotionCurve.standard.animation(MotionDuration.quick), value: bufferingShownAt == nil)
        // the panels rise over Emphasis and leave over Standard on Exit, as the board's sheets do (Reduce Motion fades them on the same clock)
        .animation(panel == nil ? MotionCurve.exit.animation(MotionDuration.standard) : MotionCurve.standard.animation(MotionDuration.emphasis), value: panel)
        // re-reads the clock once the idle time after the last input has passed
        .task(id: lastInput) {
            try? await Task.sleep(for: .seconds(PlayerChrome.idle + 0.05))
            now = .now
        }
        .onChange(of: session.isPlaying) { poke() }
        .statusBarHidden(isLandscape || (!showsControls && card == nil))
        .persistentSystemOverlays(showsControls ? .automatic : .hidden)
    }

    /// The subtitle line over the video, raised above the controls in landscape and above the open panel in portrait (a sample stands in while Subtitle Style is open)
    private func subtitles(size: CGSize, isLandscape: Bool, isSidePanel: Bool, panelSize: CGSize, showsControls: Bool) -> some View {
        let text = card == nil ? session.subtitleText ?? (panel == .style ? SubtitleOverlay.sample : nil) : nil
        // the overlay sizes its line by its own height, so both orientations hand it a box as tall as the landscape screen
        let side = min(size.width, size.height)
        let presentation = session.player.currentItem?.presentationSize ?? .zero
        let aspect = presentation.width > 0 && presentation.height > 0 ? presentation.width / presentation.height : 16 / 9
        let videoBottom = (size.height + min(size.height, size.width / aspect)) / 2
        let width = isLandscape && isSidePanel ? size.width - panelSize.width - 60 : size.width
        let bottom = if isLandscape {
            size.height - (showsControls ? 96 : 0)
        } else if isSidePanel {
            min(videoBottom, size.height - panelSize.height - 8)
        } else {
            videoBottom
        }
        return SubtitleOverlay(text: text)
            .frame(width: width, height: side)
            .offset(y: bottom - side)
            // the line moves with the controls and the panel over Standard, and snaps under Reduce Motion
            .animation(reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.standard), value: bottom)
    }

    /// The top bar with Close and the title, the skip and play buttons on the video's centre, and the scrubber over the bottom row
    private func controls(size: CGSize, insets: EdgeInsets, isLandscape: Bool) -> some View {
        let item = session.item
        let isEpisode = item.type == .episode
        let title = isEpisode ? item.seriesName ?? session.title : session.title
        let subtitle = isEpisode ? "\(episodeCode(item)) · \(session.title)" : item.productionYear.map(String.init)
        return ZStack {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .black.opacity(0.12), location: 0.3),
                .init(color: .black.opacity(0.12), location: 0.62),
                .init(color: .black.opacity(0.7), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    PlayerGlassButton(systemImage: "xmark", label: "Close") { close() }
                    VStack(spacing: 1) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Self.text.opacity(0.7))
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    // balances Close, so the title stays centred
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer(minLength: 0)
                VStack(spacing: isLandscape ? 4 : 14) {
                    PlayerScrubber(session: session, isScrubbing: $isScrubbing, onInput: poke)
                    bottomRow(isLandscape: isLandscape)
                }
            }
            .padding(.top, isLandscape ? 18 : insets.top)
            .padding(.horizontal, isLandscape ? max(insets.leading, insets.trailing) + 2 : 20)
            .padding(.bottom, isLandscape ? 14 : insets.bottom + 18)
            HStack(spacing: isLandscape ? 56 : 34) {
                Button { skip(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 30, weight: .medium))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back 10 seconds")
                Button {
                    poke()
                    if session.isPlaying { session.player.pause() } else { session.player.play() }
                } label: {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34))
                        // the buffering spinner sits over the button in place of its symbol
                        .opacity(bufferingShownAt == nil ? 1 : 0)
                        .frame(width: 72, height: 72)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Color(rgb: 0x3C3C44).opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                        .contentShape(Circle())
                }
                .accessibilityLabel(session.isPlaying ? "Pause" : "Play")
                Button { skip(by: 10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 30, weight: .medium))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Forward 10 seconds")
            }
            .buttonStyle(.pressable)
        }
        .frame(width: size.width, height: size.height)
    }

    /// The speed pill leading, then Audio & Subtitles, the next episode and the turn to the other orientation
    private func bottomRow(isLandscape: Bool) -> some View {
        HStack {
            Button {
                poke()
                panel = panel == .speed ? nil : .speed
            } label: {
                Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "×")
                    .font(.system(size: 14.5, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 28)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(panel == .speed ? .white.opacity(0.22) : .black.opacity(0.25), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Playback speed")
            .accessibilityValue(rate.formatted() + "×")
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button {
                    poke()
                    panel = .tracks
                } label: {
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 21))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(panel == .tracks || panel == .style ? 0.22 : 0), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel("Audio & Subtitles")
                if let next = neighbors.next {
                    Button {
                        poke()
                        play(next)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 19))
                            if isLandscape {
                                Text("Next Episode")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .accessibilityLabel("Next episode")
                }
                Button {
                    poke()
                    // the player turns with the phone afterwards, as both orientations stay allowed while it shows
                    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                    scene?.requestGeometryUpdate(.iOS(interfaceOrientations: isLandscape ? .portrait : .landscapeRight))
                } label: {
                    Image(systemName: isLandscape ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate")
                        .font(.system(size: 19))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel(isLandscape ? "Turn to portrait" : "Turn to landscape")
            }
        }
        .buttonStyle(.pressable)
    }

    /// Any tap or control shows the controls and restarts the idle time
    private func poke() {
        lastInput = .now
        now = lastInput
    }

    /// A tap on the video closes the speed menu, otherwise hides the controls when they show and shows them when they don't
    private func tap(showsControls: Bool) {
        if panel != nil {
            panel = nil
            poke()
        } else if showsControls {
            // an idle time long past hides the bars at once, unless playback is paused or loading
            lastInput = .distantPast
            now = .now
        } else {
            poke()
        }
    }

    private func close() {
        Task { await connection.stopPlayback() }
    }

    private func skip(by delta: Double) {
        poke()
        let target = max(0, session.player.currentTime().seconds + delta)
        session.player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// Plays a neighbouring episode in this player, from the position Jellyfin holds for it, unless the player closed or moved on during the fetch (a failed fetch shows the player's Can't play alert)
    private func play(_ neighbor: EpisodeNeighbors.Neighbor) {
        countdown.cancel()
        guard let id = neighbor.episode.jellyfinID else { return }
        let current = session
        attemptPlay {
            guard let service = connection.service else { return }
            let item = try await service.item(id: id)
            // Close or another play during the fetch replaced this session, so the next episode no longer belongs on screen
            guard connection.playback === current else { return }
            await connection.play(item)
        }
    }
}

/// The starting state: the blurred poster with the title, the resume point and the server's note, and Close
private struct PlayerStarting: View {
    let connection: JellyfinConnection
    let session: PlaybackSession
    let size: CGSize
    let insets: EdgeInsets
    /// Whether the artwork grows into the screen (the play that opened the player) or shows filled
    let growsArtwork: Bool

    var body: some View {
        let isLandscape = size.width > size.height
        let item = session.item
        let isEpisode = item.type == .episode
        let title = isEpisode ? item.seriesName ?? session.title : session.title
        let resume = session.resumeTicks > 0 ? "Resumes at \(PlayerChrome.clock(Double(session.resumeTicks) / 10_000_000))" : nil
        let detail = [isEpisode ? episodeCode(item) : nil, resume].compactMap(\.self).joined(separator: " · ")
        ZStack(alignment: .topLeading) {
            PlayerArtwork(url: connection.posterURL(item, maxWidth: 300), grows: growsArtwork)
                .frame(width: size.width, height: size.height)
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                VStack(spacing: 4) {
                    Text(title)
                        .font(.custom("Archivo-SemiBold", size: 24, relativeTo: .title2))
                        .tracking(-0.48)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 14))
                            .foregroundStyle(MobilePlayerView.text.opacity(0.7))
                    }
                }
                .accessibilityElement(children: .combine)
                Text("\(connection.serverName ?? "Jellyfin") is preparing the stream…")
                    .font(.system(size: 14))
                    .foregroundStyle(MobilePlayerView.text.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(width: size.width, height: size.height)
            // the loading state arrives once the artwork fills the screen
            .entrance(after: growsArtwork ? MotionDuration.morph : 0)
            PlayerGlassButton(systemImage: "xmark", label: "Close") { Task { await connection.stopPlayback() } }
                .padding(.top, isLandscape ? 18 : insets.top)
                .padding(.leading, isLandscape ? max(insets.leading, insets.trailing) + 2 : 20)
        }
        .frame(width: size.width, height: size.height)
        .statusBarHidden(isLandscape)
    }
}

/// The playback error with the reason, Try Again from the same position and Back
private struct PlayerFailure: View {
    let connection: JellyfinConnection
    let session: PlaybackSession
    let message: String
    let isLandscape: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(rgb: 0xFF8A8D))
                .accessibilityHidden(true)
            Text(session.item.type == .episode ? "Can’t play this episode" : "Can’t play this movie")
                .font(.custom("Archivo-SemiBold", size: 22, relativeTo: .title2))
                .tracking(-0.44)
            Text(message)
                .font(.system(size: 14.5))
                .lineSpacing(3)
                .foregroundStyle(MobilePlayerView.text.opacity(0.7))
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                Button {
                    Task { await connection.play(session.item, atTicks: session.resumeTicks) }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(Color(rgb: 0x101014))
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(MobilePlayerView.text, in: Capsule())
                        .contentShape(Capsule())
                }
                Button { Task { await connection.stopPlayback() } } label: {
                    Text("Back")
                        .font(.system(size: 15.5, weight: .semibold))
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(.white.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                }
            }
            .buttonStyle(.pressable)
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, isLandscape ? 120 : 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .statusBarHidden(isLandscape)
    }
}

/// The elapsed time, the scrubber with the buffered range, and the time left
private struct PlayerScrubber: View {
    let session: PlaybackSession
    /// Set while the scrubber is dragged, which keeps the controls up
    @Binding var isScrubbing: Bool
    let onInput: () -> Void

    /// The scrubber's fraction while dragging, nil otherwise (gesture state, so a cancelled drag clears it too)
    @GestureState private var scrub: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var duration: Double {
        if session.duration > 0 { return session.duration }
        let seconds = session.player.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    private var position: Double {
        scrub.map { $0 * duration } ?? session.seconds
    }

    /// The end of the loaded range around the playhead, which the session's ten-a-second position refresh redraws
    private var buffered: Double {
        let now = session.player.currentTime()
        let range = session.player.currentItem?.loadedTimeRanges.map(\.timeRangeValue).first { $0.containsTime(now) }
        let end = range?.end.seconds ?? 0
        return end.isFinite ? end : 0
    }

    var body: some View {
        VStack(spacing: -10) {
            GeometryReader { proxy in
                let fraction = duration > 0 ? min(1, max(0, position / duration)) : 0
                let loaded = duration > 0 ? min(1, max(fraction, buffered / duration)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 6)
                    Capsule().fill(.white.opacity(0.3)).frame(width: proxy.size.width * loaded, height: 6)
                    Capsule().fill(MobilePlayerView.text).frame(width: proxy.size.width * fraction, height: 6)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        // the thumb grows under the finger, and Reduce Motion keeps it still
                        .scaleEffect(scrub == nil || reduceMotion ? 1 : 1.4)
                        .offset(x: proxy.size.width * fraction - 7)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
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
                .animation(MotionCurve.standard.animation(MotionDuration.press), value: scrub == nil)
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(PlayerChrome.clock(position)) of \(PlayerChrome.clock(duration))")
                .accessibilityAdjustableAction { direction in
                    onInput()
                    let delta: Double = direction == .increment ? 10 : -10
                    session.player.seek(to: CMTime(seconds: max(0, session.seconds + delta), preferredTimescale: 600))
                }
            }
            .frame(height: 44)
            HStack {
                Text(PlayerChrome.clock(position))
                Spacer()
                Text("-" + PlayerChrome.clock(max(0, duration - position)))
            }
            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
            .foregroundStyle(MobilePlayerView.text.opacity(0.75))
            .accessibilityHidden(true)
        }
    }
}

/// The round glass button of the player's top bar
private struct PlayerGlassButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .background(Color(rgb: 0x3C3C44).opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

/// The card in an episode's credits: Up Next, the next episode's still, code and runtime, title and synopsis, then Play with the countdown and Cancel
private struct PlayerNextEpisodeCard: View {
    let next: EpisodeNeighbors.Neighbor
    /// Seconds left on the countdown
    let remaining: Int
    let isLandscape: Bool
    let play: () -> Void
    let cancel: () -> Void

    var body: some View {
        let still: CGFloat = isLandscape ? 150 : 132
        VStack(alignment: .leading, spacing: 10) {
            Text("UP NEXT")
                .font(.system(size: 12.5, weight: .bold))
                .tracking(0.75)
                .foregroundStyle(MobilePlayerView.text.opacity(0.6))
            HStack(alignment: .top, spacing: 14) {
                CachedImage(url: Config.tmdbImageURL(path: next.episode.posterPath, size: "w300"), maxPixel: 300) {
                    Color.white.opacity(0.08)
                }
                .frame(width: still, height: still * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(next.episode.runtime > 0
                        ? "S\(next.season) · E\(next.episode.number) · \(next.episode.runtime) min"
                        : "S\(next.season) · E\(next.episode.number)")
                        .font(.system(size: 13))
                        .foregroundStyle(MobilePlayerView.text.opacity(0.65))
                    Text(next.episode.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    if !next.episode.overview.isEmpty {
                        Text(next.episode.overview)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .foregroundStyle(MobilePlayerView.text.opacity(0.65))
                            .lineLimit(3)
                            // the still beside it would otherwise hold the synopsis to one line
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 10) {
                Button(action: play) {
                    Label("Play in \(remaining)", systemImage: "play.fill")
                        .font(.system(size: 15.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(rgb: 0x101014))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(MobilePlayerView.text, in: Capsule())
                        .contentShape(Capsule())
                }
                .accessibilityLabel("Play next episode")
                .accessibilityValue("Plays in \(remaining) seconds")
                Button(action: cancel) {
                    Text("Cancel")
                        .font(.system(size: 15.5, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.white.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                }
            }
            .buttonStyle(.pressable)
            .padding(.top, 4)
        }
    }
}

/// AVPlayerLayer on the session's player, fitting the video inside its frame
private struct VideoLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        view.playerLayer?.player = player
        view.playerLayer?.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: VideoLayerView, context: Context) {
        // the next episode or Try Again brings a new session's player into the same view
        if view.playerLayer?.player !== player { view.playerLayer?.player = player }
    }
}

/// A view backed by an AVPlayerLayer, so the video follows its bounds
private final class VideoLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
}
