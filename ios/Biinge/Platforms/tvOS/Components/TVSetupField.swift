import SwiftUI

extension View {
    /// The Apple TV setup screens' text field: its text on a translucent rounded box that turns white with dark text while focused, ringed red when invalid
    func tvSetupField(text: String, prompt: String, isSecure: Bool = false, isFocused: Bool, isInvalid: Bool = false) -> some View {
        let shown = isSecure ? String(repeating: "•", count: text.count) : text
        // tvOS draws its own platter on a text field in every style, which grows past the box on focus, so the field stays all but transparent (still focusable at 2%) and the box draws the text
        return foregroundStyle(.clear)
            .opacity(0.02)
            .overlay(alignment: .leading) {
                Text(text.isEmpty ? prompt : shown)
                    .lineLimit(1)
                    // the end of a long entry stays in view, as the field shows it
                    .truncationMode(.head)
                    .foregroundStyle(isFocused ? Color.biingeFocusText : Color.biingeText)
                    .opacity(text.isEmpty ? 0.55 : 1)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 40))
            .padding(.horizontal, 32)
            .frame(width: 1000, height: 96)
            .background(isFocused ? Color.biingeFocusFill : Color.biingeFill(0.1), in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(isInvalid ? Color.biingeError : Color.biingeFill(isFocused ? 0 : 0.18), lineWidth: 2)
            )
            .shadow(color: Color.biingeShadow.opacity(isFocused ? 0.45 : 0), radius: 20, y: 18)
            .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
    }
}
