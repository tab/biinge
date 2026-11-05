import SwiftUI

/// A failed load's message and Retry over the posters an earlier load brought (the prototype's library banner)
struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 18))
                .foregroundStyle(Color.biingeError)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.biingeText.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.biingeFill(0.12), in: Capsule())
                    // the banner's inset counts toward the button, so the touch target is 44 pt tall
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.biingeFill(0.08)))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
