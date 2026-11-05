import SwiftUI

/// Full-bleed poster wall behind the Apple TV and Mac setup screens, dimmed on dark and washed toward the background on light, under a radial and a bottom gradient
struct SetupBackground: View {
    // lighter than the setup mockups' dark values, so the posters stay visible behind the form
    #if os(macOS)
    private let brightness = 0.72
    private let scale = 1.04
    private let radial = (center: 0.15, edge: 0.5)
    private let bottom = 0.3
    /// The light mockup's radial wash: center, at 45 %, edge
    private let lightRadial = (center: 0.9, middle: 0.6, middleAt: 0.45, edge: 0.2)
    private let lightBrightness = 0.95
    private let lightSaturation = 0.8
    private let lightBlur = 0.0
    #else
    private let brightness = 0.7
    private let scale = 1.05
    private let radial = (center: 0.15, edge: 0.55)
    private let bottom = 0.3
    /// The light mockup's radial wash: center, at 50 %, edge
    private let lightRadial = (center: 0.9, middle: 0.74, middleAt: 0.5, edge: 0.45)
    private let lightBrightness = 1.0
    private let lightSaturation = 0.7
    private let lightBlur = 5.0
    #endif

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        // the light theme washes the wall with the background color where the dark one darkens it with black
        let wash = isLight ? Color.biingeBackground : .black
        // the gradients take the screen's size; the filled image sits behind them and may overflow it
        ZStack {
            // the CSS ellipse reaches the corners at 100%, which is half the frame's diagonal: 70% of that is 0.495 here
            EllipticalGradient(
                stops: isLight
                    ? [
                        .init(color: wash.opacity(lightRadial.center), location: 0),
                        .init(color: wash.opacity(lightRadial.middle), location: lightRadial.middleAt),
                        .init(color: wash.opacity(lightRadial.edge), location: 1),
                    ]
                    : [
                        .init(color: wash.opacity(radial.center), location: 0),
                        .init(color: wash.opacity(radial.edge), location: 1),
                    ],
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.495
            )

            LinearGradient(
                stops: isLight
                    ? [
                        .init(color: wash.opacity(0), location: 0),
                        .init(color: wash.opacity(0), location: 0.7),
                        .init(color: wash.opacity(0.6), location: 1),
                    ]
                    : [
                        .init(color: wash.opacity(0), location: 0),
                        .init(color: wash.opacity(bottom), location: 0.6),
                        .init(color: wash.opacity(0.85), location: 1),
                    ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .background {
            // colorMultiply is CSS brightness(): it scales each channel instead of adding to it
            Image("LoginBackground")
                .resizable()
                .scaledToFill()
                .scaleEffect(scale)
                .colorMultiply(Color(white: isLight ? lightBrightness : brightness))
                .saturation(isLight ? lightSaturation : 0.9)
                .blur(radius: isLight ? lightBlur : 0)
        }
        .background(wash)
        .ignoresSafeArea()
    }
}
