import SwiftUI

/// The poster grid's two columns, which its skeleton shares
private let posterGridColumns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
]

/// A scrolling two-column grid of poster cells (4:6 posters, matching the RN grid), where a removed poster shrinks out on Exit over Quick and the rest reflow over Emphasis (Reduce Motion fades it out and cuts to the new order)
struct PosterGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder let cell: (Item) -> Cell

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let removal: AnyTransition = reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
        ScrollView {
            LazyVGrid(columns: posterGridColumns, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    cell(item)
                        .environment(\.posterFadeIndex, index)
                        // Undo fades the poster back in as the gap opens
                        .transition(.asymmetric(insertion: .opacity, removal: removal.animation(MotionCurve.exit.animation(MotionDuration.quick))))
                }
            }
            .padding(8)
            .animation(reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.emphasis), value: items.map(\.id))
        }
    }
}

/// The poster grid's loading skeleton, in the grid's own columns and spacing
struct PosterGridSkeleton: View {
    /// The parent's hold, which keeps the skeleton 500 ms once it shows
    @Binding var isHeld: Bool

    var body: some View {
        ScrollView {
            LazyVGrid(columns: posterGridColumns, spacing: 8) {
                ForEach(0..<8, id: \.self) { _ in
                    PosterSkeleton()
                }
            }
            .padding(8)
        }
        .scrollDisabled(true)
        .loadingSkeleton(isHeld: $isHeld)
    }
}
