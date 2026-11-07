import SwiftUI

/// The Apple TV setup screens' pill button: translucent at rest on dark, a raised white pill on light, and lit and raised while focused (Reduce Motion: lit without the scale)
struct TVSetupButtonStyle: ButtonStyle {
    /// A primary button rests at white 28% instead of 12% on dark, and a shade darker on light
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(label: configuration.label, isPrimary: isPrimary)
    }

    /// Reads focus and the appearance from the environment, which a ButtonStyle itself can't see
    private struct Pill: View {
        let label: ButtonStyleConfiguration.Label
        let isPrimary: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let isLight = colorScheme == .light
            // the light mockup rests the pills on raised white, the primary one on a light grey
            let rest = isLight ? Color(rgb: isPrimary ? 0xCECED2 : 0xFFFFFF) : .white.opacity(isPrimary ? 0.28 : 0.12)
            label
                .font(.system(size: 32, weight: .semibold))
                // the mockups' primary pill: light on dark, dark on light, which stands out from the white rest pills
                .foregroundStyle(isFocused ? Color.biingeBackground : Color.biingeText)
                .padding(.horizontal, 48)
                .frame(height: 84)
                .background(isFocused ? Color.biingeText : rest, in: Capsule())
                .scaleEffect(isFocused && !reduceMotion ? 1.08 : 1)
                .shadow(color: Color.biingeShadow.opacity(isFocused ? 0.5 : isLight ? 0.3 : 0), radius: isFocused ? 25 : 8, y: isFocused ? 24 : 4)
                .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
        }
    }
}
