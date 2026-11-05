import JellyfinAPI
import SwiftUI

extension View {
    /// Plays the bound item, through the resume sheet when Jellyfin stores a position for it (nil onGoTo leaves out the sheet's Go to row)
    func tvPlayChoice(_ item: Binding<BaseItemDto?>, connection: JellyfinConnection, onGoTo: ((TVRoute) -> Void)?) -> some View {
        modifier(PlayChoice(item: item, connection: connection, onGoTo: onGoTo))
    }
}

/// What the resume sheet chose
private enum PlayChoiceAction {
    case play(BaseItemDto, fromStart: Bool)
    /// Opens the details of the item's movie, or of its series for an episode
    case goTo(BaseItemDto)
}

/// Presents the resume sheet for an item with a stored position and acts on the choice once the sheet has closed
private struct PlayChoice: ViewModifier {
    @Binding var item: BaseItemDto?
    let connection: JellyfinConnection
    let onGoTo: ((TVRoute) -> Void)?

    /// Held until the sheet is gone, so the player or the pushed screen doesn't present during its dismissal
    @State private var choice: PlayChoiceAction?
    /// The last item shown, so the sheet keeps its content while it animates out after the binding clears
    @State private var lastItem: BaseItemDto?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                isPresented: Binding(
                    get: { (item?.userData?.playbackPositionTicks ?? 0) > 0 },
                    set: { if !$0 { item = nil } }
                ),
                onDismiss: {
                    switch choice {
                    case .play(let chosen, let fromStart): Task { await connection.play(chosen, fromStart: fromStart) }
                    case .goTo(let chosen):
                        Task {
                            guard let service = connection.service else { return }
                            do {
                                // an episode's series TMDB ID needs a fetch of the series, and a title without one opens nothing
                                if let title = try await DetailsTitle.resolve(chosen, service: service) { onGoTo?(.title(title, poster: connection.posterURL(chosen, maxWidth: 880))) }
                            } catch {
                                // a failed fetch opens nothing, and a revoked token disconnects
                                _ = await connection.handleFailure(error)
                            }
                        }
                    case nil: break
                    }
                    choice = nil
                },
                content: {
                    if let shown = item ?? lastItem {
                        ResumeSheet(item: shown, connection: connection, offersGoTo: onGoTo != nil && (shown.type == .episode || DetailsTitle(shown) != nil)) { action in
                            choice = action
                            self.item = nil
                        }
                    }
                }
            )
            // an item without a stored position skips the sheet
            .onChange(of: item?.id) {
                if let item { lastItem = item }
                guard let chosen = item, (chosen.userData?.playbackPositionTicks ?? 0) == 0 else { return }
                item = nil
                Task { await connection.play(chosen) }
            }
    }
}

/// The resume sheet over the blurred, dimmed screen: the art with its progress, then Resume, Play from Beginning and Go to
private struct ResumeSheet: View {
    let item: BaseItemDto
    let connection: JellyfinConnection
    /// Whether the Go to row shows (off on the screen it would go to)
    let offersGoTo: Bool
    let choose: (PlayChoiceAction) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let isMovie = item.type == .movie
        let title = (isMovie ? item.name : item.seriesName) ?? ""
        let subtitle = isMovie
            ? [item.productionYear.map(String.init) ?? "", duration(ticks: item.runTimeTicks ?? 0)].filter { !$0.isEmpty }.joined(separator: " · ")
            : "\(episodeCode(item)) · \(item.name ?? "")"
        let left = duration(ticks: (item.runTimeTicks ?? 0) - (item.userData?.playbackPositionTicks ?? 0))
        HStack(spacing: 80) {
            PosterImage(title: title, cornerRadius: 0, poster: connection.landscapeURL(item, maxWidth: 1280), frame: CGSize(width: 640, height: 360), titleFont: .system(size: 26), titlePadding: 20)
                .overlay(alignment: .bottom) {
                    PlaybackBar(fraction: (item.userData?.playedPercentage ?? 0) / 100, height: 8, inset: 0)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 22)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.biingeText.opacity(0.12), lineWidth: 1))
                .shadow(color: Color.biingeShadow.opacity(0.6), radius: 45, y: 40)
            VStack(alignment: .leading, spacing: 16) {
                Text("Continue Watching · \(isMovie ? "Movie" : "TV Show")")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Color.biingeText.opacity(0.65))
                Text(title)
                    .font(.system(size: 56, weight: .bold))
                    .tracking(-1.68)
                Text(subtitle)
                    .font(.system(size: 27))
                    .foregroundStyle(Color.biingeText.opacity(0.7))
                    .padding(.bottom, 18)
                Button { choose(.play(item, fromStart: false)) } label: {
                    Label("Resume · \(left) left", systemImage: "play.fill")
                }
                Button { choose(.play(item, fromStart: true)) } label: {
                    Label("Play from Beginning", systemImage: "arrow.counterclockwise")
                }
                if offersGoTo {
                    Button { choose(.goTo(item)) } label: {
                        Label(isMovie ? "Go to Movie" : "Go to Show", systemImage: "info.circle.fill")
                    }
                }
            }
            .buttonStyle(SheetButtonStyle())
            .frame(width: 620, alignment: .leading)
        }
        .foregroundStyle(Color.biingeText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.biingeScrim.opacity(0.55))
                .ignoresSafeArea()
        }
        .onExitCommand { dismiss() }
    }
}

/// The resume and details menu sheets' full-width row button: translucent at rest, light and raised while focused, with red text when destructive
struct SheetButtonStyle: ButtonStyle {
    /// Red at rest and deep red on the light focus fill (a menu's Remove)
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        Row(label: configuration.label, isDestructive: isDestructive)
    }

    /// Reads focus from the environment, which a ButtonStyle itself can't see
    private struct Row: View {
        let label: ButtonStyleConfiguration.Label
        let isDestructive: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let text = switch (isFocused, isDestructive) {
            case (true, true): Color(rgb: 0xC4262B)
            case (true, false): Color.biingeFocusText
            case (false, true): Color.biingeError
            case (false, false): Color.biingeText
            }
            label
                .labelStyle(RowLabelStyle())
                .font(.system(size: 31, weight: .semibold))
                .foregroundStyle(text)
                // a row with a description grows past the one-line height
                .padding(.vertical, 12)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                .background(isFocused ? Color.biingeFocusFill : Color.biingeText.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                // Reduce Motion keeps the light fill as the focus mark and drops the lift
                .scaleEffect(isFocused && !reduceMotion ? 1.05 : 1)
                .shadow(color: Color.biingeShadow.opacity(isFocused ? 0.4 : 0), radius: 20, y: 18)
                .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
        }
    }

    /// The mockup's 38 px icon 16 px before the label
    private struct RowLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 16) {
                configuration.icon.font(.system(size: 28, weight: .semibold))
                configuration.title
            }
        }
    }
}
