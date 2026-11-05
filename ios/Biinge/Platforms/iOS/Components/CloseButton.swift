import SwiftUI

/// The X every modal closes with, floating over the top-left of its content (a back chevron on a screen pushed inside a modal)
struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var back = false
    /// The glass circle's diameter (the touch target stays 44 pt)
    var size: CGFloat = 44

    var body: some View {
        // dismiss pops a pushed screen and closes a sheet's root, so one action covers both
        Button { dismiss() } label: {
            Image(systemName: back ? "chevron.left" : "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.biingeText)
                .frame(width: size, height: size)
                .background(reduceTransparency ? Color.biingeCard : .clear, in: Circle())
                .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(back ? "Back" : "Close")
        .padding(.leading, 16)
        .padding(.top, 16)
    }
}
