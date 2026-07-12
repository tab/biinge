import SwiftUI

/// Pin marker shown on pinned library items (top-right).
struct PinBadge: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(25))
            .padding(6)
            .background(.black.opacity(0.6), in: Circle())
            .padding(6)
    }
}

/// Watch-progress pie shown on watching shows (top-left).
struct ProgressBadge: View {
    let percent: Double

    var body: some View {
        PieChartView(percent: percent, color: .white)
            .frame(width: 22, height: 22)
            .padding(6)
    }
}
