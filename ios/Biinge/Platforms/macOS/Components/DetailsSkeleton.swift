import SwiftUI

/// The movie and series details' loading skeleton in their header's layout: the poster beside the kind, title and facts lines, the action row and the overview where they land
struct DetailsSkeleton: View {
    /// The poster's width, at 2:3
    let posterWidth: CGFloat
    /// The parent's hold, which keeps the skeleton 500 ms once it shows
    @Binding var isHeld: Bool

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 48) {
                SkeletonBlock(cornerRadius: 16)
                    .frame(width: posterWidth, height: posterWidth * 1.5)
                VStack(alignment: .leading, spacing: 18) {
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 64, height: 15)
                    SkeletonBlock(cornerRadius: 12)
                        .frame(width: 420, height: 64)
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 280, height: 16)
                    HStack(spacing: 12) {
                        SkeletonBlock(cornerRadius: 24)
                            .frame(width: 200, height: 48)
                        SkeletonBlock(cornerRadius: 24)
                            .frame(width: 170, height: 48)
                        SkeletonBlock(cornerRadius: 24)
                            .frame(width: 48, height: 48)
                    }
                    SkeletonBlock(cornerRadius: 6)
                        .frame(maxWidth: 600)
                        .frame(height: 56)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 100)
            .padding(.horizontal, 40)
            .padding(.bottom, 80)
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .loadingSkeleton(isHeld: $isHeld)
    }
}
