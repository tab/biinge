import SwiftUI

// Badges sit on artwork, so they keep the prototype's dark scrim and light ink in both appearances

/// Pin marker shown on pinned library items (top-right)
struct PinBadge: View {
    var body: some View {
        #if os(tvOS)
        // the Apple TV details poster's pin, sized for the room
        let size: CGFloat = 52, glyph: CGFloat = 22, weight: Font.Weight = .regular, inset: CGFloat = 18, label = "Pinned to Up Next"
        #else
        let size: CGFloat = 26, glyph: CGFloat = 12, weight: Font.Weight = .semibold, inset: CGFloat = 8, label = "Pinned"
        #endif
        Image(systemName: "pin.fill")
            .font(.system(size: glyph, weight: weight))
            .rotationEffect(.degrees(25))
            .foregroundStyle(Color(rgb: 0xF4F4F2))
            .frame(width: size, height: size)
            .background(.black.opacity(0.6), in: Circle())
            .padding(inset)
            .accessibilityLabel(label)
    }
}

/// Watched / in-library check shown on posters (top-left)
struct WatchedBadge: View {
    /// The details poster's size, which the boards draw larger on iPhone and Mac
    var isLarge = false

    var body: some View {
        #if os(tvOS)
        // the Apple TV episode rows' check, sized for the room
        let size: CGFloat = 40, glyph: CGFloat = 22, radius: CGFloat = 8, inset: CGFloat = 12
        #elseif os(macOS)
        let size: CGFloat = isLarge ? 28 : 24, glyph: CGFloat = isLarge ? 15 : 13, radius: CGFloat = isLarge ? 6 : 5, inset: CGFloat = isLarge ? 10 : 7
        #else
        let size: CGFloat = isLarge ? 26 : 22, glyph: CGFloat = isLarge ? 13 : 12, radius: CGFloat = isLarge ? 6 : 5, inset: CGFloat = isLarge ? 8 : 6
        #endif
        Image(systemName: "checkmark")
            .font(.system(size: glyph, weight: .bold))
            .foregroundStyle(Color(rgb: 0xF4F4F2))
            .frame(width: size, height: size)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .padding(inset)
            .accessibilityLabel("In your library")
    }
}

/// The watched check on a details poster, arriving 80 ms after the Watched icon pops on Focus over Standard and leaving on Exit over Quick (Reduce Motion fades it)
private struct DetailWatchedBadge: ViewModifier {
    let isWatched: Bool

    /// Starts at the title's state, so details open with the badge already in place
    @State private var showsBadge: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isWatched: Bool) {
        self.isWatched = isWatched
        _showsBadge = State(initialValue: isWatched)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if showsBadge {
                    WatchedBadge(isLarge: true)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
            }
            // keyed on the state, so a toggle back within the 80 ms cancels the pending badge
            .task(id: isWatched) {
                guard isWatched != showsBadge else { return }
                if isWatched {
                    // the badge follows the button, so the eye moves from the action to its result
                    guard (try? await Task.sleep(for: .milliseconds(80))) != nil else { return }
                    withAnimation(MotionCurve.focus.animation(MotionDuration.standard)) { showsBadge = true }
                } else {
                    withAnimation(MotionCurve.exit.animation(MotionDuration.quick)) { showsBadge = false }
                }
            }
    }
}

/// The check on a movie or series poster whose title sits on a biinge list, read from the live stores so a change shows at once
private struct TrackedBadge: ViewModifier {
    let title: DetailsTitle?
    let scale: CGFloat

    @Environment(MovieStore.self) private var movies
    @Environment(SeriesStore.self) private var series

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if title?.state(movies: movies, series: series) != nil {
                    WatchedBadge()
                        .scaleEffect(scale, anchor: .topLeading)
                }
            }
    }
}

extension View {
    /// Badges this details poster while the title is watched, following the Watched icon's pop (top-left)
    func detailWatchedBadge(_ isWatched: Bool) -> some View {
        modifier(DetailWatchedBadge(isWatched: isWatched))
    }

    /// Badges this poster while its title sits on a biinge list (top-left; `scale` fits a thumbnail smaller than a poster)
    func trackedBadge(_ title: DetailsTitle?, scale: CGFloat = 1) -> some View {
        modifier(TrackedBadge(title: title, scale: scale))
    }
}

/// Watch-progress pie shown on watching shows (top-left)
struct ProgressBadge: View {
    let percent: Double

    var body: some View {
        PieChartView(percent: percent, color: Color(rgb: 0xF4F4F2))
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .padding(8)
            .accessibilityLabel("Watch progress")
            .accessibilityValue("\(Int(percent.rounded())) percent")
    }
}

/// Recently added marker (top-right)
struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.system(size: 11, weight: .bold))
            .tracking(0.44)
            .foregroundStyle(Color.biingePrimary)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(9)
            .accessibilityLabel("New")
    }
}

/// Resume position along a poster's bottom edge (`fraction` is the played share, 0 to 1)
struct PlaybackBar: View {
    let fraction: Double
    var height: CGFloat = 4
    /// The space around the bar on every edge
    var inset: CGFloat = 10

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.3))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color(rgb: 0xF4F4F2))
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(Capsule())
            .frame(height: height)
            .padding(inset)
            .accessibilityElement()
            .accessibilityLabel("Playback progress")
            .accessibilityValue("\(Int((min(max(fraction, 0), 1) * 100).rounded())) percent")
    }
}

/// The "Not on <server>" note on a poster the server doesn't hold (bottom-left)
struct NotOnServerBadge: View {
    let server: String

    var body: some View {
        Label("Not on \(server)", systemImage: "circle.slash")
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .frame(height: 26)
            .background(.black.opacity(0.62), in: Capsule())
            .padding(8)
    }
}
