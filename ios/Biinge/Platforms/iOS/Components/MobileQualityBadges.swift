import SwiftUI

/// The outlined quality badges that follow a details screen's kind label, as in "Movie 4K HDR ATMOS"
struct MobileQualityBadges: View {
    let badges: [String]

    var body: some View {
        ForEach(badges, id: \.self) { badge in
            Text(badge)
                .font(.caption2.weight(.bold))
                .tracking(0.44)
                .foregroundStyle(Color.biingeText.opacity(0.88))
                .padding(.vertical, 2)
                .padding(.horizontal, 7)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.biingeText.opacity(0.45), lineWidth: 1.5))
                .fixedSize()
        }
    }
}
