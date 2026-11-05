import SwiftUI

/// The art blurred, saturated and dimmed across the full Apple TV screen, reaching past its edges so the blur's soft edge falls outside
struct TVBackdropArt: View {
    let url: URL?

    var body: some View {
        CachedImage(url: url, maxPixel: 640) { Color.clear }
            .frame(width: 1920 + 320, height: 1080 + 320)
            .blur(radius: 90)
            .saturation(1.5)
            // colorMultiply is CSS brightness(): it scales each channel instead of adding to it
            .colorMultiply(Color.biingeBackdropBrightness)
            .frame(width: 1920, height: 1080)
            .clipped()
    }
}
