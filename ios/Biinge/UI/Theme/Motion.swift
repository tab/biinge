import SwiftUI

/// One of the motion board's cubic Bézier curves by its two control points (design/prototype/Biinge Motion.dc.html)
struct MotionCurve: Equatable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    /// Most motion: entrances, hovers, toggles and page slides
    static let standard = MotionCurve(x1: 0.2, y1: 0.7, x2: 0.2, y2: 1)
    /// Things leaving, which accelerate out
    static let exit = MotionCurve(x1: 0.4, y1: 0, x2: 1, y2: 1)
    /// The small overshoot of Apple TV focus and icon pops, nowhere else
    static let focus = MotionCurve(x1: 0.34, y1: 1.36, x2: 0.64, y2: 1)
    /// Progress that tracks time, such as the countdown ring
    static let linear = MotionCurve(x1: 0, y1: 0, x2: 1, y2: 1)

    /// The curve run over a duration in seconds (one of `MotionDuration`)
    func animation(_ duration: TimeInterval) -> Animation {
        .timingCurve(x1, y1, x2, y2, duration: duration)
    }

    /// The curve as a keyframe's timing curve
    var unitCurve: UnitCurve {
        .bezier(startControlPoint: UnitPoint(x: x1, y: y1), endControlPoint: UnitPoint(x: x2, y: y2))
    }
}

/// The motion board's durations in seconds
enum MotionDuration {
    /// A button press scaling to 97%
    static let press: TimeInterval = 0.12
    /// Hover, toggles, colour changes and exits
    static let quick: TimeInterval = 0.2
    /// Apple TV focus, menus, page slides and toasts
    static let standard: TimeInterval = 0.28
    /// Sheets and grid reflow
    static let emphasis: TimeInterval = 0.45
    /// Shared-element morphs between screens
    static let morph: TimeInterval = 0.55
    /// Hero crossfades, never on a user action
    static let ambient: TimeInterval = 0.8
    /// How long a load runs before its skeleton shows, so a fast load never flashes one
    static let skeletonDelay: TimeInterval = 0.3
    /// How long playback stalls before its spinner shows, so a short stall never flashes one
    static let stallDelay: TimeInterval = 0.5
    /// The least time a skeleton or playback spinner stays once shown, so it never flickers
    static let loadingHold: TimeInterval = 0.5
    /// The playback spinner and its dim leaving on Exit
    static let stallExit: TimeInterval = 0.15
    /// One sweep of the skeleton shimmer, which loops
    static let shimmer: TimeInterval = 1.4
    /// A failed field's message leaving on Exit
    static let buttonExit: TimeInterval = 0.15
    /// How long a failed field's message waits behind its ring
    static let follow: TimeInterval = 0.08
    /// The Mac login fields' one shake when the login fails
    static let shake: TimeInterval = 0.4
    /// The gap between neighbouring posters fading in
    static let posterStagger: TimeInterval = 0.04
    /// How many posters stagger their fade-in, about the first screenful
    static let staggeredPosters = 12

    /// The delay before the poster at `index` fades in (40 ms per place over the first screenful, none after it or with Reduce Motion)
    static func posterFadeDelay(at index: Int, reduceMotion: Bool) -> TimeInterval {
        reduceMotion || index >= staggeredPosters ? 0 : Double(index) * posterStagger
    }

    /// How long the playback spinner waits at `now` before it changes: the 500 ms stall before it shows, the rest of its 500 ms hold before it hides, nil while it stays as it is
    static func stallWait(isBuffering: Bool, shownAt: Date?, now: Date) -> TimeInterval? {
        switch (isBuffering, shownAt) {
        case (true, nil): stallDelay
        case (false, let shownAt?): max(0, loadingHold - now.timeIntervalSince(shownAt))
        default: nil
        }
    }
}

/// The Want and Watched icon pop: the new symbol grows from half size as the old one shrinks away, on Focus over Standard turning on and on Standard over Quick turning off (Reduce Motion crossfades them)
private struct IconPop: ViewModifier {
    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // the stack holds the leaving and the arriving symbol in one place while they cross
        ZStack {
            content
                .id(isOn)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
        }
        .animation(isOn ? MotionCurve.focus.animation(MotionDuration.standard) : MotionCurve.standard.animation(MotionDuration.quick), value: isOn)
    }
}

extension View {
    /// Pops this toggle's symbol when `isOn` changes (apply it to the symbol alone, before its frame and background)
    func iconPop(_ isOn: Bool) -> some View {
        modifier(IconPop(isOn: isOn))
    }
}

/// A details entrance: on its first appearance the view rises 10 pt into place and fades in over Standard after `delay`, and Reduce Motion fades it in over Quick at once
private struct Entrance: ViewModifier {
    let delay: TimeInterval

    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 10)
            .onAppear {
                let animation = reduceMotion
                    ? MotionCurve.standard.animation(MotionDuration.quick)
                    : MotionCurve.standard.animation(MotionDuration.standard).delay(delay)
                withAnimation(animation) { isShown = true }
            }
    }
}

extension View {
    /// Fades this view in on its first appearance (details stagger their text 60 ms apart, the player its loading text after the artwork's Morph)
    func entrance(after delay: TimeInterval = 0) -> some View {
        modifier(Entrance(delay: delay))
    }
}

/// A list row's arrival: it fades in over Standard 40 ms after the row before it (over the first screenful), and Reduce Motion fades the rows in together
private struct RowFade: ViewModifier {
    let index: Int

    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .onAppear {
                let delay = MotionDuration.posterFadeDelay(at: index, reduceMotion: reduceMotion)
                withAnimation(MotionCurve.standard.animation(MotionDuration.standard).delay(delay)) { isShown = true }
            }
    }
}

/// A details backdrop's arrival: it fades in over Emphasis 150 ms after the content, as the page's largest image
private struct BackdropFade: ViewModifier {
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .onAppear {
                withAnimation(MotionCurve.standard.animation(MotionDuration.emphasis).delay(0.15)) { isShown = true }
            }
    }
}

extension View {
    /// Fades this list row in on its first appearance, staggered by its place in the list
    func rowFade(at index: Int) -> some View {
        modifier(RowFade(index: index))
    }

    /// Fades this details backdrop in on its first appearance, after the content
    func backdropFade() -> some View {
        modifier(BackdropFade())
    }
}

/// The details-to-player artwork: the poster grows from a poster-sized frame in the middle to fill the player over Morph, then blurs and dims under the loading state (Reduce Motion fills at once and only fades the blur in)
struct PlayerArtwork: View {
    let url: URL?
    /// Whether the poster grows in, otherwise it shows filled, blurred and dimmed from the start (a later item in an open player)
    let grows: Bool

    @State private var isGrown = false
    @State private var isSettled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isFull = isGrown || reduceMotion || !grows
            let isBlurred = isSettled || !grows
            // the details poster's share of the screen, 2:3
            let width = isFull ? size.width : min(size.width, size.height) * 0.4
            CachedImage(url: url, maxPixel: 300) { Color.clear }
                .frame(width: width, height: isFull ? size.height : width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: isFull ? 0 : 14, style: .continuous))
                .blur(radius: isBlurred ? 50 : 0, opaque: true)
                .saturation(isBlurred ? 1.3 : 1)
                .overlay(Color.black.opacity(isBlurred ? 0.6 : 0))
                .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard grows else { return }
            guard !reduceMotion else {
                withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { isSettled = true }
                return
            }
            withAnimation(MotionCurve.standard.animation(MotionDuration.morph)) {
                isGrown = true
            } completion: {
                withAnimation(MotionCurve.standard.animation(MotionDuration.standard)) { isSettled = true }
            }
        }
    }
}

extension AnyTransition {
    /// A failed field's message: it slides down 4 pt into place over Quick 80 ms after the ring and leaves on Exit (Reduce Motion only fades it)
    static func fieldMessage(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: (reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(y: -4)))
                .animation(MotionCurve.standard.animation(MotionDuration.quick).delay(MotionDuration.follow)),
            removal: .opacity.animation(MotionCurve.exit.animation(MotionDuration.buttonExit))
        )
    }
}
