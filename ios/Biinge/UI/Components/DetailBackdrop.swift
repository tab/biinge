import SwiftUI

/// The poster blurred behind a details header, fading into the page (washed out in light mode so dark text reads)
struct DetailBackdrop: View {
    let url: URL?
    /// The backdrop's height (nil fills the space it is offered)
    var height: CGFloat? = 640
    var blur: CGFloat = 60
    var saturation: Double = 1.5
    /// How far the blurred art reaches past each edge, so the blur's soft edge falls outside the header
    var bleed: CGFloat = 100
    /// Where the fade into the page starts, as a share of the height
    var fadeStart: Double = 0.35
    /// How far the backdrop draws up past the content's top (the iPhone's status bar sits on the art)
    var topOverlap: CGFloat = 100
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.clear.overlay {
                CachedImage(url: url, maxPixel: 640) { Color.clear }
                    .blur(radius: blur)
                    .saturation(saturation)
                    // colorMultiply is CSS brightness(): it scales each channel instead of adding to it
                    .colorMultiply(Color.biingeBackdropBrightness)
                    .padding(-bleed)
            }
            Color.biingeBackground.opacity(colorScheme == .light ? 0.7 : 0)
            LinearGradient(
                stops: [.init(color: Color.biingeBackground.opacity(0), location: fadeStart), .init(color: Color.biingeBackground, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: height)
        .clipped()
        .padding(.top, -topOverlap)
        .backdropFade()
        .accessibilityHidden(true)
    }
}
