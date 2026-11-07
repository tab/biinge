import SwiftUI

/// Press feedback for tappable content: dims on touch-down, and shrinks unless Reduce Motion is on
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(MotionCurve.standard.animation(MotionDuration.press), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// Stands in for `.plain` wherever a tap needs feedback before it commits
    static var pressable: PressableStyle { PressableStyle() }
}
