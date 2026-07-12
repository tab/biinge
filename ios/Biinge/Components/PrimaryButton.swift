import SwiftUI

/// The brand call-to-action: an accent-filled pill with black text and a
/// loading state, used for the primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label
                .font(.biingeCallout)
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.biingePrimary.opacity(isEnabled ? 1 : 0.5))
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
