import SwiftUI

/// Pin marker shown on pinned library items (top-right)
struct PinBadge: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(25))
            .padding(6)
            .background(.black.opacity(0.6), in: Circle())
            .padding(6)
            .accessibilityLabel("Pinned")
    }
}

/// Watched / in-library check shown on posters (top-left)
struct WatchedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(6)
            .accessibilityLabel("In your library")
    }
}

/// Watch-progress pie shown on watching shows (top-left)
struct ProgressBadge: View {
    let percent: Double

    var body: some View {
        PieChartView(percent: percent, color: .white)
            .frame(width: 18, height: 18)
            .padding(6)
            .accessibilityLabel("Watch progress")
            .accessibilityValue("\(Int(percent.rounded())) percent")
    }
}
