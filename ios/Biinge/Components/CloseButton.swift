import SwiftUI

/// The X every modal closes with, floating over the top-left of its content (a back chevron on a screen pushed inside a modal)
struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var back = false

    var body: some View {
        // dismiss pops a pushed screen and closes a sheet's root, so one action covers both
        Button { dismiss() } label: {
            Image(systemName: back ? "chevron.left" : "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel(back ? "Back" : "Close")
        .padding(.leading, 16)
        .padding(.top, 16)
    }
}
