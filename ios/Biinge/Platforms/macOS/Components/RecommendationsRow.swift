import SwiftUI

/// The details screens' Recommendations row of posters, each opening its title's details and marked when the library holds it
struct RecommendationsRow: View {
    let items: [Recommendation]
    /// The library state of a title by its ID
    let state: @MainActor (Int) -> WatchState?
    let poster: (Recommendation) -> URL?
    let route: (Recommendation) -> DesktopRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recommendations")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .padding(.horizontal, 40)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in
                        NavigationLink(value: route(item)) {
                            VStack(alignment: .leading, spacing: 10) {
                                PosterImage(title: item.title, cornerRadius: 0, poster: poster(item),
                                            frame: CGSize(width: 164, height: 246), titleFont: .system(size: 14), titlePadding: 12)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.biingeText.opacity(0.07), lineWidth: 1))
                                    .overlay(alignment: .topLeading) {
                                        if state(item.id) != nil { WatchedBadge() }
                                    }
                                    .posterHover(cornerRadius: 10)
                                Text(item.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .frame(width: 164, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.title)
                            .accessibilityValue(state(item.id) != nil ? "In your library" : "")
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}
