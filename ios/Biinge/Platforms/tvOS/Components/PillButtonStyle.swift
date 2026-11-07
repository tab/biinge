import SwiftUI

/// The Apple TV hero and details pill: an icon and a label, translucent at rest, light and raised while focused (Reduce Motion: lit without the scale)
struct PillButtonStyle: ButtonStyle {
    /// Shows only the label's icon in a circle (the details' •••)
    var isIconOnly = false
    /// Rests near-white with dark text (the details' next step)
    var isPrimary = false
    /// Dims the pill at rest and while focused, which it still takes (the play while the server is unreachable)
    var isDisabled = false
    /// Ends the label with the chevron that says it opens a menu (the details' list pill)
    var isMenu = false
    /// Shows the pin before the chevron (the list pill of a pinned title)
    var isPinned = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(label: configuration.label, style: self)
    }

    /// Reads focus from the environment, which a ButtonStyle itself can't see
    private struct Pill: View {
        let label: ButtonStyleConfiguration.Label
        let style: PillButtonStyle

        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let fill = if style.isDisabled {
                Color.biingeText.opacity(isFocused ? 0.2 : 0.07)
            } else if isFocused {
                Color.biingeFocusFill
            } else if style.isPrimary {
                Color.biingeFocusFill.opacity(0.88)
            } else {
                Color.biingeText.opacity(0.16)
            }
            let text = if style.isDisabled {
                Color.biingeText.opacity(isFocused ? 0.6 : 0.38)
            } else if isFocused || style.isPrimary {
                Color.biingeFocusText
            } else {
                Color.biingeText
            }
            HStack(spacing: 10) {
                label
                    .labelStyle(PillLabelStyle(isIconOnly: style.isIconOnly))
                if style.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 22))
                        .rotationEffect(.degrees(25))
                        .accessibilityLabel("Pinned")
                }
                if style.isMenu {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 27, weight: .semibold))
                        .opacity(0.6)
                        .padding(.leading, -6)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 31, weight: .semibold))
            .foregroundStyle(text)
            .padding(.leading, style.isIconOnly ? 0 : 32)
            .padding(.trailing, style.isIconOnly ? 0 : style.isMenu ? 26 : 40)
            .frame(minWidth: style.isIconOnly ? 76 : nil)
            .frame(height: 76)
            .background(fill, in: Capsule())
            .scaleEffect(isFocused && !reduceMotion ? 1.08 : 1)
            .shadow(color: Color.biingeShadow.opacity(isFocused ? 0.45 : 0), radius: 20, y: 18)
            .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
        }
    }

    /// The mockup's 40 px icon 10 px before the label, or the icon alone
    private struct PillLabelStyle: LabelStyle {
        let isIconOnly: Bool

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 10) {
                configuration.icon.font(.system(size: 30, weight: .semibold))
                if !isIconOnly { configuration.title }
            }
        }
    }
}
