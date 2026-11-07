import SwiftUI

/// Sets a header above the content and slides it up as the first scroll view inside scrolls, so the list takes the freed space (a pull-down leaves it in place)
struct CollapsingHeader<Header: View>: ViewModifier {
    @ViewBuilder let header: Header

    /// How far the scroll view has moved past its resting top (0 at rest and on a pull-down)
    @State private var scrolled: CGFloat = 0
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                scrolled = max(offset, 0)
            }
            // the inset keeps its height, so the list scrolls up into the space the header leaves
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                    .offset(y: -scrolled)
                    .opacity(height > 0 ? Double(max(0, 1 - scrolled / height)) : 1)
                    .allowsHitTesting(scrolled < height / 2)
            }
    }
}
