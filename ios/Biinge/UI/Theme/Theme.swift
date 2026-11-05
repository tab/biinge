import SwiftUI
#if os(macOS)
import AppKit

extension NSColor {
    convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#else
import UIKit

extension UIColor {
    convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

extension Appearance {
    /// The color scheme the app is forced into, nil for System
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

extension Color {
    init(rgb: UInt) {
        #if os(macOS)
        self.init(nsColor: NSColor(rgb: rgb))
        #else
        self.init(uiColor: UIColor(rgb: rgb))
        #endif
    }

    /// A color that resolves to `light` or `dark` based on the active interface style (each at its own opacity)
    static func adaptive(light: UInt, dark: UInt, lightOpacity: Double = 1, darkOpacity: Double = 1) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(rgb: dark).withAlphaComponent(darkOpacity)
                : NSColor(rgb: light).withAlphaComponent(lightOpacity)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark).withAlphaComponent(darkOpacity)
                : UIColor(rgb: light).withAlphaComponent(lightOpacity)
        })
        #endif
    }

    // Brand
    /// The brand yellow, the same in both appearances (`biingeRating` is the adaptive one)
    static let biingePrimary = Color(rgb: 0xEEC01E)
    /// The red accent (Mac and Apple TV only; the iPhone restyle has no accent)
    static let biingeAccent = Color(rgb: 0xE5484D)
    /// Loader tint: white on dark surfaces, a visible gray on light ones
    static let biingeLoader = adaptive(light: 0x6E6969, dark: 0xFFFFFF)

    // Every platform: the light and dark values of design/prototype/biinge-theme.js
    static let biingeBackground = adaptive(light: 0xF3F3F1, dark: 0x101014)
    /// A panel one step off the background
    static let biingeSurface = adaptive(light: 0xEAEAE7, dark: 0x17171D)
    /// A raised panel or card
    static let biingeCard = adaptive(light: 0xFFFFFF, dark: 0x1B1B20)
    /// Primary text, and at lower opacities secondary text, rest fills and card rings
    static let biingeText = adaptive(light: 0x16161A, dark: 0xF4F4F2)
    /// Secondary text: dates, labels and section headings
    static let biingeTextSecondary = adaptive(light: 0x62626A, dark: 0x91919A)
    static let biingeTextTertiary = adaptive(light: 0x8C8C94, dark: 0x64646D)
    /// A focused card's title and a focused row's heading
    static let biingeTextFocused = adaptive(light: 0x000000, dark: 0xFFFFFF)
    /// A focused pill or sheet button's fill
    static let biingeFocusFill = adaptive(light: 0xFFFFFF, dark: 0xF4F4F2)
    /// Text on a focused fill
    static let biingeFocusText = Color(rgb: 0x101014)
    /// The missing-art and chip fill
    static let biingeSecondaryCard = adaptive(light: 0xDEDED9, dark: 0x282828)
    /// The missing-art title, placeholder titles and quiet labels
    static let biingeGrayDark = adaptive(light: 0x8E8A8A, dark: 0x6E6969)
    /// Watched and connected
    static let biingeWatched = adaptive(light: 0x1F9A52, dark: 0x34C46F)
    /// New and rating stars
    static let biingeRating = adaptive(light: 0xA77D00, dark: 0xEEC01E)
    /// Error text
    static let biingeError = adaptive(light: 0xC8383D, dark: 0xFF8A8D)
    /// Shadow under cards and pills (a grey on light, so the same opacity reads softer)
    static let biingeShadow = adaptive(light: 0x5A5A64, dark: 0x000000)
    /// Multiplied into the blurred hero backdrop (CSS brightness 0.6 on dark, none on light)
    static let biingeBackdropBrightness = adaptive(light: 0xFFFFFF, dark: 0x999999)
    /// The resume sheet's tint over the blurred screen
    static let biingeScrim = adaptive(light: 0xF4F4F2, dark: 0x0A0A0C)

    /// The prototypes' white fill at the opacity, which turns black at three quarters of it on light
    static func biingeFill(_ opacity: Double) -> Color {
        adaptive(light: 0x000000, dark: 0xFFFFFF, lightOpacity: opacity * 0.75, darkOpacity: opacity)
    }

    // Data: chart marks only (bars, dots and split bars), the same in both appearances
    /// Movies in a chart (oklch .70 .16 295)
    static let dataMovies = Color(rgb: 0xA787F6)
    /// Series in a chart (oklch .80 .12 210)
    static let dataSeries = Color(rgb: 0x47D2E8)

    // Grays
    /// A fixed light gray for text over artwork
    static let biingeGray = Color(rgb: 0xB5B5B5)
}
