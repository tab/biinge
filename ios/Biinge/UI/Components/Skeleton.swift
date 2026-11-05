import SwiftUI

/// A loading placeholder: a rounded fill a soft highlight sweeps across on the 1.4 s Shimmer loop (Reduce Motion keeps the plain fill)
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.biingeSecondaryCard)
            .overlay {
                if !reduceMotion {
                    // one clock for every block, so the sweeps on screen run in step
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: MotionDuration.shimmer) / MotionDuration.shimmer
                        LinearGradient(colors: [.clear, .white.opacity(colorScheme == .dark ? 0.06 : 0.45), .clear], startPoint: .leading, endPoint: .trailing)
                            .visualEffect { content, proxy in content.offset(x: (phase * 2 - 1) * proxy.size.width) }
                    }
                    .clipShape(shape)
                }
            }
    }
}

/// A poster card's loading placeholder: the 2:3 art, then a title line and a shorter subtitle line when `caption` gives the title's height
struct PosterSkeleton: View {
    var cornerRadius: CGFloat = 12
    /// The title line's height, nil for the art alone
    var caption: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: (caption ?? 0) * 0.8) {
            SkeletonBlock(cornerRadius: cornerRadius)
                .aspectRatio(2 / 3, contentMode: .fit)
            if let caption {
                // the lines take a share of the card's width, the way the board's title and year do
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: caption * 0.5) {
                        SkeletonBlock(cornerRadius: caption / 2)
                            .frame(width: proxy.size.width * 0.75, height: caption)
                        SkeletonBlock(cornerRadius: caption / 2)
                            .frame(width: proxy.size.width * 0.5, height: caption * 0.8)
                    }
                }
                .frame(height: caption * 2.3)
            }
        }
    }
}

/// Holds a loading skeleton back for 300 ms, so a load that lands sooner never flashes it, then holds `isHeld` for 500 ms once it shows, fades it out on removal once shown, and reads it to VoiceOver as one Loading element
struct LoadingSkeleton: ViewModifier {
    /// Set for the 500 ms after the skeleton shows, while the parent keeps the skeleton in place of what loaded
    @Binding var isHeld: Bool

    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            // one that never showed leaves at once, which cancels its timer before a late hold can bring it back
            .transition(isShown ? .opacity.animation(MotionCurve.standard.animation(MotionDuration.standard)) : .identity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
            .task {
                await Self.time { held in
                    // the skeleton shows as its hold starts and stays shown once the hold ends
                    isShown = true
                    isHeld = held
                }
            }
    }

    /// Waits out the 300 ms delay, then calls `held` with true and, once the 500 ms hold ends, false (a cancel during the delay calls nothing, and one during the hold ends it at once)
    static func time(held: (Bool) -> Void) async {
        // a load that lands first removes the skeleton, which cancels the sleep
        guard (try? await Task.sleep(for: .seconds(MotionDuration.skeletonDelay))) != nil else { return }
        held(true)
        // a skeleton that leaves the screen sooner, such as a closed screen, ends its hold too
        try? await Task.sleep(for: .seconds(MotionDuration.loadingHold))
        held(false)
    }
}

extension View {
    /// Shows this skeleton layout only once loading has run 300 ms, then sets `isHeld` for 500 ms (the parent shows the skeleton while it is set, so a shown skeleton never flickers, and removing it fades a shown one out and cuts an unshown one at once)
    func loadingSkeleton(isHeld: Binding<Bool>) -> some View {
        modifier(LoadingSkeleton(isHeld: isHeld))
    }
}
