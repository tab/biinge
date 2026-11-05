import SwiftUI

/// The outlined quality badges that follow a details screen's kind label, as in "Movie 4K HDR ATMOS"
struct TVQualityBadges: View {
    let badges: [String]

    var body: some View {
        ForEach(badges, id: \.self) { badge in
            Text(badge)
                .font(.system(size: 21, weight: .bold))
                .tracking(0.84)
                .foregroundStyle(Color.biingeText.opacity(0.9))
                .padding(.vertical, 3)
                .padding(.horizontal, 12)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.biingeText.opacity(0.5), lineWidth: 2))
                .fixedSize()
        }
    }
}
