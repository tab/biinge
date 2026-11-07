import SwiftUI

/// The Mac poster hover: the artwork lifts 4 pt with a shadow over Quick under the pointer or while its card has keyboard focus, and Reduce Motion keeps only the shadow
private struct PosterHover: ViewModifier {
    let cornerRadius: CGFloat

    @State private var isHovered = false
    /// Whether the card around the poster has keyboard focus (its nearest focusable ancestor)
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isLifted = isHovered || isFocused
        content
            .shadow(color: Color.biingeShadow.opacity(isLifted ? 0.5 : 0), radius: 14, y: 14)
            .offset(y: isLifted && !reduceMotion ? -4 : 0)
            // the hover area stays where the poster rests, so a pointer at its lower edge doesn't flicker the lift
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: isLifted)
    }
}

extension View {
    /// Lifts this poster artwork under the pointer or keyboard focus (its caption stays put, as it sits outside the modifier)
    func posterHover(cornerRadius: CGFloat) -> some View {
        modifier(PosterHover(cornerRadius: cornerRadius))
    }
}
