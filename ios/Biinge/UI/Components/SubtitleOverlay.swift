import SwiftUI

/// The shown subtitle line over the video in the device's subtitle style, sized and raised in proportion to the player's height
struct SubtitleOverlay: View {
    let text: String?

    @AppStorage(SubtitleSize.key) private var size = SubtitleSize.medium
    @AppStorage(SubtitleWeight.key) private var weight = SubtitleWeight.regular
    @AppStorage(SubtitleBackground.key) private var background = SubtitleBackground.shadow
    @AppStorage(SubtitleHeight.key) private var height = SubtitleHeight.standard

    /// The line the Subtitle Style preview shows between cues
    static let sample = "Do you remember what you wanted to be?"

    var body: some View {
        GeometryReader { proxy in
            if let text {
                let points = proxy.size.height * 0.042 * size.scale
                let isBox = background == .box
                Text(text)
                    .font(.system(size: points, weight: weight.fontWeight))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    // None keeps a faint edge under the glyphs, Shadow adds a wide glow, Box puts a dark backing behind them
                    .shadow(color: .black.opacity(background == .shadow ? 0.9 : 0), radius: points * 0.12)
                    .shadow(color: .black.opacity(isBox ? 0 : 0.7), radius: points * 0.04, y: points * 0.04)
                    .padding(.horizontal, isBox ? points * 0.4 : 0)
                    .padding(.vertical, isBox ? points * 0.15 : 0)
                    .background(.black.opacity(isBox ? 0.6 : 0), in: RoundedRectangle(cornerRadius: points * 0.2))
                    .frame(maxWidth: proxy.size.width * 0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, proxy.size.height * height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension SubtitleWeight {
    /// The font weight the line is drawn in
    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .bold: .bold
        }
    }
}
