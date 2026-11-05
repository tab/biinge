import SwiftUI

/// The black and white switch, at the system switch's size: on is a `biingeText` track under a `biingeCard` knob, off a dim track under a white knob, and a tap anywhere on the label or switch flips it
struct SwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label
                // the system switch can't draw this: its knob stays white whatever the tint, which hides it on a white track
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.biingeText : Color.biingeFill(0.28))
                    Capsule()
                        .fill(configuration.isOn ? Color.biingeCard : .white)
                        .frame(width: 37, height: 24)
                        .padding(2)
                }
                .frame(width: 63, height: 28)
                .animation(reduceMotion ? nil : MotionCurve.standard.animation(MotionDuration.quick), value: configuration.isOn)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
