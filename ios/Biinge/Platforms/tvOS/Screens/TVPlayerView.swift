import AVKit
import JellyfinAPI
import SwiftUI

/// Full-screen Apple TV player: the starting state, AVKit's transport bar with the title and the Audio & Subtitles and Next Episode actions, the drawn subtitles, the tracks panel and the next-episode card, or the playback error with Try Again and Back
struct TVPlayerView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let session: PlaybackSession

    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsTracks = false
    @State private var showsStyle = false
    /// The playing episode's neighbours (none until they load, and none for a movie)
    @State private var neighbors = EpisodeNeighbors()
    @State private var countdown = NextEpisodeCountdown()
    @FocusState private var focusesRetry: Bool
    /// The session that opened the player, nil until its first appearance (only its artwork grows; the next episode and Try Again show theirs filled)
    @State private var openedSession: ObjectIdentifier?
    /// Set while the opening play's artwork grows, so the poster holds the screen for the whole Morph even when the stream is ready sooner
    @State private var isArtworkGrowing = true

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
        // the player stays dark in the light appearance
        .environment(\.colorScheme, .dark)
        // the cover shows the screen beneath by default, which would show around a letterboxed or shrunk video
        .presentationBackground(.black)
        .onAppear { openedSession = ObjectIdentifier(session) }
        // the artwork's phase runs on its own clock, so Menu still leaves at any point (Reduce Motion has no phase and crossfades)
        .task {
            if !reduceMotion { try? await Task.sleep(for: .seconds(MotionDuration.morph)) }
            isArtworkGrowing = false
        }
        .onExitCommand { exit() }
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
        // every item, the next episode's too, opens with its own neighbours and countdown and the panel closed
        .task(id: ObjectIdentifier(session)) {
            neighbors = EpisodeNeighbors()
            countdown = NextEpisodeCountdown()
            showsTracks = false
            showsStyle = false
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
    }

    @ViewBuilder
    private var player: some View {
        // the panel opens only on a loaded stream, whose tracks it lists
        let panelStream = showsTracks ? session.stream : nil
        // the credits card shrinks the video to 42 % toward the leading side, where it keeps playing (Reduce Motion keeps it full size)
        let isShrunk = card != nil && !reduceMotion
        // the card slides in from the right as the video shrinks, and leaves faster (Reduce Motion fades it)
        let cardSlide: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 20))
        ZStack {
            // AVKit's controls step aside while the panel or the card takes the remote
            PlayerController(session: session, showsControls: panelStream == nil && card == nil,
                             showsSample: panelStream != nil && showsStyle, next: neighbors.next, playNext: { play($0) }, openTracks: {
                // the transport bar keeps this action across items, so it reads the playing session from the connection
                guard connection.playback?.stream != nil else { return }
                showsStyle = false
                showsTracks = true
            })
            // the container scales, so AVKit lays out at full size; the radius and ring read 22 pt and 3 pt once shrunk
            .clipShape(RoundedRectangle(cornerRadius: isShrunk ? 22 / 0.42 : 0, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: isShrunk ? 22 / 0.42 : 0, style: .continuous)
                .strokeBorder(.white.opacity(isShrunk ? 0.14 : 0), lineWidth: 3 / 0.42)
                .allowsHitTesting(false))
            // the anchor leaves the shrunk video 5 % in from the leading edge and a quarter of the way down, as the board places it
            .scaleEffect(isShrunk ? 0.42 : 1, anchor: UnitPoint(x: 0.086, y: 0.428))
            // the clip, ring and scale above measure the safe area, so the screen-sized frame has to reach them
            .ignoresSafeArea()
            // the poster grows from the middle to fill the screen and holds it while the server prepares the stream, then crossfades into the video
            if session.stream == nil || isArtworkGrowing {
                ZStack {
                    PlayerArtwork(url: connection.posterURL(session.item, maxWidth: 300), grows: growsArtwork)
                        .background(.black)
                        .ignoresSafeArea()
                    starting
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            if let card, let remaining = countdown.remaining {
                TVNextEpisodeCard(next: card, remaining: remaining) {
                    play(card)
                } cancel: {
                    countdown.cancel()
                }
                .transition(.asymmetric(
                    insertion: cardSlide.animation(MotionCurve.standard.animation(MotionDuration.emphasis).delay(0.25)),
                    removal: cardSlide.animation(MotionCurve.exit.animation(MotionDuration.quick))
                ))
            } else if let panelStream {
                TracksPanel(session: session, stream: panelStream, showsStyle: $showsStyle)
                    .transition(.opacity)
            }
        }
        // Cancel grows the video back from wherever the shrink has reached
        .animation(MotionCurve.standard.animation(MotionDuration.morph), value: card == nil)
        // the panel fades in over Emphasis and out over Standard on Exit, as the board's sheets do
        .animation(panelStream == nil ? MotionCurve.exit.animation(MotionDuration.standard) : MotionCurve.standard.animation(MotionDuration.emphasis), value: panelStream == nil)
        .animation(MotionCurve.standard.animation(MotionDuration.standard), value: session.stream == nil || isArtworkGrowing)
    }

    /// The starting state over the artwork: the spinner, title, episode code, resume point and the server's note
    private var starting: some View {
        let item = session.item
        let isEpisode = item.type == .episode
        let resume = session.resumeTicks > 0 ? "Resumes at \(PlayerChrome.clock(Double(session.resumeTicks) / 10_000_000))" : nil
        let detail = [isEpisode ? episodeCode(item) : nil, resume].compactMap(\.self).joined(separator: " · ")
        return VStack(spacing: 28) {
            ProgressView()
                .tint(.white)
            Text(isEpisode ? item.seriesName ?? session.title : session.title)
                .font(.system(size: 56, weight: .semibold))
                .tracking(56 * -0.03)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 30))
                    .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.7))
            }
            Text("\(connection.serverName ?? "Jellyfin") is preparing the stream…")
                .font(.system(size: 28))
                .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.55))
        }
        .foregroundStyle(Color(rgb: 0xF4F4F2))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 200)
        // the loading state arrives once the artwork fills the screen
        .entrance(after: growsArtwork ? MotionDuration.morph : 0)
    }

    /// Menu steps back out of Subtitle Style, then out of the panel, then out of the player (the card leaves the player, as Escape does on Mac)
    private func exit() {
        if card == nil, showsTracks, showsStyle {
            showsStyle = false
        } else if card == nil, showsTracks {
            showsTracks = false
        } else {
            Task { await connection.stopPlayback() }
        }
    }

    /// Plays a neighbouring episode in this player, from the position Jellyfin holds for it, unless the player closed or moved on during the fetch (a failed fetch shows the player's Can't play alert)
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

    /// The playback error over the dark radial backdrop, with Try Again from the same position (focused) and Back
    private func failure(_ message: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 88))
                .foregroundStyle(Color(rgb: 0xFF8A8D))
            Text(session.item.type == .episode ? "Can’t play this episode" : "Can’t play this movie")
                .font(.system(size: 64, weight: .bold))
                .tracking(-1.9)
            Text(message)
                .font(.system(size: 30))
                .lineSpacing(10)
                .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1100)
            HStack(spacing: 24) {
                Button {
                    Task { await connection.play(session.item, atTicks: session.resumeTicks) }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .focused($focusesRetry)
                Button {
                    Task { await connection.stopPlayback() }
                } label: {
                    Label("Back", systemImage: "arrow.left")
                }
            }
            .buttonStyle(PillButtonStyle())
            .padding(.top, 20)
        }
        .foregroundStyle(Color(rgb: 0xF4F4F2))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Color(rgb: 0x17171D), .black], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 1100)
                .ignoresSafeArea()
        )
        .defaultFocus($focusesRetry, true)
    }
}

/// AVPlayerViewController on the session's player, with the drawn subtitles in its content overlay, the title in its transport bar and the Audio & Subtitles and Next Episode actions
private struct PlayerController: UIViewControllerRepresentable {
    let session: PlaybackSession
    /// Off while the panel or the card holds the remote
    let showsControls: Bool
    /// Whether the sample line stands in between cues, while Subtitle Style is open
    let showsSample: Bool
    /// The episode the Next Episode action plays, nil while there's none, which hides the action
    let next: EpisodeNeighbors.Neighbor?
    let playNext: @MainActor (EpisodeNeighbors.Neighbor) -> Void
    let openTracks: @MainActor () -> Void

    /// The transport bar's actions (Next Episode carries its episode's ID as its identifier, which tells when the items need replacing)
    private var menuItems: [UIMenuElement] {
        // AVPlayer lists only the selected audio track, and the stream carries no subtitles, so one action opens our panel for both
        // (the sliders keep it apart from AVKit's own subtitle bubble beside it)
        var items: [UIMenuElement] = [UIAction(title: "Audio & Subtitles", image: UIImage(systemName: "slider.horizontal.3")) { _ in openTracks() }]
        if let next, let id = next.episode.jellyfinID {
            items.append(UIAction(title: "Next Episode", image: UIImage(systemName: "forward.end"), identifier: UIAction.Identifier(id)) { _ in playNext(next) })
        }
        return items
    }

    /// The hosted subtitle line, whose session and sample change with the view
    func makeCoordinator() -> UIHostingController<Subtitles> {
        UIHostingController(rootView: Subtitles(session: session, showsSample: showsSample))
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = session.player
        // the content overlay sits between the video and the transport bar, so the bar covers the subtitle
        let subtitles = context.coordinator
        subtitles.view.backgroundColor = .clear
        subtitles.view.translatesAutoresizingMaskIntoConstraints = false
        controller.addChild(subtitles)
        if let overlay = controller.contentOverlayView {
            overlay.addSubview(subtitles.view)
            NSLayoutConstraint.activate([
                subtitles.view.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                subtitles.view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
                subtitles.view.topAnchor.constraint(equalTo: overlay.topAnchor),
                subtitles.view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            ])
        }
        subtitles.didMove(toParent: controller)
        controller.transportBarCustomMenuItems = menuItems
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // the next episode brings a new session's player into the same controller
        if controller.player !== session.player { controller.player = session.player }
        let subtitles = context.coordinator
        if subtitles.rootView.session !== session || subtitles.rootView.showsSample != showsSample {
            subtitles.rootView = Subtitles(session: session, showsSample: showsSample)
        }
        controller.showsPlaybackControls = showsControls
        // the focused player view spans the screen, so a swipe finds no row inside it; an unfocusable view hands focus to the panel or the card
        controller.view.isUserInteractionEnabled = showsControls
        // the neighbours load after the player opens, and each item's action must play from its own session
        let shownNext = controller.transportBarCustomMenuItems.dropFirst().first as? UIAction
        if shownNext?.identifier.rawValue != next?.episode.jellyfinID { controller.transportBarCustomMenuItems = menuItems }
        // each stream, an audio switch's too, loads into a new player item, which takes the title for the transport bar
        guard session.stream != nil, let current = session.player.currentItem, current.externalMetadata.isEmpty else { return }
        let item = session.item
        // an episode reads "Series · S1 · E4" above its title, a movie its year
        let above = item.type == .episode
            ? [item.seriesName, episodeCode(item)].compactMap { $0 }.joined(separator: " · ")
            : item.productionYear.map(String.init) ?? ""
        current.externalMetadata = [(AVMetadataIdentifier.commonIdentifierTitle, session.title), (.iTunesMetadataTrackSubTitle, above)]
            .filter { !$0.1.isEmpty }
            .map { identifier, value in
                let metadata = AVMutableMetadataItem()
                metadata.identifier = identifier
                metadata.value = value as NSString
                metadata.extendedLanguageTag = "und"
                return metadata
            }
    }
}

/// The session's subtitle line, or the sample between cues while Subtitle Style is open, hosted in the player's content overlay
private struct Subtitles: View {
    let session: PlaybackSession
    let showsSample: Bool

    var body: some View {
        SubtitleOverlay(text: session.subtitleText ?? (showsSample ? SubtitleOverlay.sample : nil))
            .ignoresSafeArea()
    }
}

/// What the tracks panel can focus
private enum TrackFocus: Hashable {
    case audio(Int)
    /// A subtitle stream, -1 for Off
    case subtitle(Int)
}

/// The Audio & Subtitles panel over the top of the video: Audio, Subtitles with Off, and Options with Subtitle Style, or the Subtitle Style page
private struct TracksPanel: View {
    let session: PlaybackSession
    let stream: PlaybackStream
    @Binding var showsStyle: Bool

    @AppStorage(SubtitleSize.key) private var size = SubtitleSize.medium
    @AppStorage(SubtitleBackground.key) private var background = SubtitleBackground.shadow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The panel opens on the shown subtitle
    @FocusState private var focus: TrackFocus?

    var body: some View {
        // the pages slide 24 pt apart as they cross over Standard, the tracks to the leading side (Reduce Motion crossfades them)
        ZStack(alignment: .top) {
            if showsStyle {
                TVSubtitleStylePage { showsStyle = false }
                    .transition((reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(x: 24)))
                        .animation(MotionCurve.standard.animation(MotionDuration.standard)))
            } else {
                tracks
                    .transition((reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(x: -24)))
                        .animation(MotionCurve.standard.animation(MotionDuration.standard)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: showsStyle ? 640 : 800, alignment: .top)
        .background(Color(rgb: 0x1E1E24).opacity(0.95), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.55), radius: 50, y: 40)
        .padding(.horizontal, 200)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))
        )
        .ignoresSafeArea()
        .foregroundStyle(Color(rgb: 0xF4F4F2))
        // the panel resizes to the new page as they slide, and snaps under Reduce Motion
        .animation(reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.standard), value: showsStyle)
    }

    private var tracks: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    header("Audio")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(stream.audioStreams, id: \.index) { track in
                                if let index = track.index {
                                    TrackRow(track: track, isSelected: index == stream.audioIndex) {
                                        Task { await session.selectAudio(index) }
                                    }
                                    .focused($focus, equals: .audio(index))
                                }
                            }
                        }
                    }
                    // the margins hold an edge row's lift and shadow, and the scroll view reaches 4 pt into the header's gap so the first row stays put
                    .contentMargins(.top, 4, for: .scrollContent)
                    .contentMargins(.bottom, 40, for: .scrollContent)
                    .padding(.top, -4)
                    .scrollClipDisabled()
                    // the lift spills sideways, but a row scrolled past either edge is cut there, clear of the header and the footer
                    .mask { Rectangle().padding(.horizontal, -40) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                VStack(alignment: .leading, spacing: 0) {
                    header("Subtitles")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            // an index of -1 or none is Off
                            TrackRow(title: "Off", detail: nil, isSelected: (session.subtitleIndex ?? -1) < 0) {
                                session.selectSubtitle(nil)
                            }
                            .focused($focus, equals: .subtitle(-1))
                            ForEach(stream.subtitleStreams, id: \.index) { track in
                                if let index = track.index {
                                    TrackRow(track: track, isSelected: index == session.subtitleIndex, isFailed: session.failedSubtitles.contains(index)) {
                                        session.selectSubtitle(index)
                                    }
                                    .focused($focus, equals: .subtitle(index))
                                }
                            }
                        }
                    }
                    // the margins hold an edge row's lift and shadow, and the scroll view reaches 4 pt into the header's gap so the first row stays put
                    .contentMargins(.top, 4, for: .scrollContent)
                    .contentMargins(.bottom, 40, for: .scrollContent)
                    .padding(.top, -4)
                    .scrollClipDisabled()
                    // the lift spills sideways, but a row scrolled past either edge is cut there, clear of the header and the footer
                    .mask { Rectangle().padding(.horizontal, -40) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                VStack(alignment: .leading, spacing: 0) {
                    header("Options")
                    Button { showsStyle = true } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "textformat.size")
                                .font(.system(size: 30))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Subtitle Style")
                                    .font(.system(size: 26, weight: .semibold))
                                Text("\(size.label) · \(background.label)")
                                    .font(.system(size: 21))
                                    .opacity(0.65)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 28, weight: .semibold))
                                .opacity(0.6)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .frame(minHeight: 96)
                    }
                    .buttonStyle(PanelButtonStyle(cornerRadius: 20))
                }
                // the section spans the panel's height, so a swipe right from any subtitle row lands on its one row
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
            }
            .padding(EdgeInsets(top: 40, leading: 44, bottom: 0, trailing: 44))
            .frame(maxHeight: .infinity, alignment: .top)
            Text("Swipe to move · Click to choose · Menu to close")
                .font(.system(size: 21))
                .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.45))
                .padding(EdgeInsets(top: 18, leading: 66, bottom: 26, trailing: 66))
        }
        .defaultFocus($focus, .subtitle(session.subtitleIndex ?? -1))
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.5))
            .padding(EdgeInsets(top: 0, leading: 22, bottom: 8, trailing: 22))
    }
}

/// One row in the tracks panel: a checkmark slot, the language, and the rest of Jellyfin's title below it (a track whose file failed says so and can't be picked)
private struct TrackRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let isFailed: Bool
    let select: () -> Void

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
            HStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 30)
                    .opacity(isSelected ? 1 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                    if isFailed {
                        Label("Couldn’t load from the server", systemImage: "exclamationmark.circle")
                            .font(.system(size: 21))
                            .foregroundStyle(Color(rgb: 0xFF8A8D))
                    } else if let detail {
                        Text(detail)
                            .font(.system(size: 22))
                            .opacity(0.65)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .frame(minHeight: 84)
        }
        .buttonStyle(PanelButtonStyle(cornerRadius: 20))
        .disabled(isFailed)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The player panels' row and option button: clear or the pick's fill at rest, light and raised while focused
struct PanelButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    /// Whether the option is the current pick, which rests on a white 22% fill
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Fill(label: configuration.label, cornerRadius: cornerRadius, isSelected: isSelected)
    }

    /// Reads focus from the environment, which a ButtonStyle itself can't see
    private struct Fill: View {
        let label: ButtonStyleConfiguration.Label
        let cornerRadius: CGFloat
        let isSelected: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .foregroundStyle(isFocused ? Color(rgb: 0x101014) : Color(rgb: 0xF4F4F2))
                .opacity(isEnabled ? 1 : 0.4)
                .background(
                    isFocused ? Color(rgb: 0xF4F4F2) : .white.opacity(isSelected ? 0.22 : 0),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                // Reduce Motion keeps the light fill as the focus mark and drops the lift
                .scaleEffect(isFocused && !reduceMotion ? 1.05 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 20, y: 18)
                .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
        }
    }
}
