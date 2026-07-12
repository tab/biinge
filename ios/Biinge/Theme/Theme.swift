import SwiftUI
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

extension Color {
    init(rgb: UInt) {
        self.init(uiColor: UIColor(rgb: rgb))
    }

    /// A color that resolves to `light` or `dark` based on the active interface style.
    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

    // Brand
    static let biingePrimary = Color(rgb: 0xEEC01E)
    static let biingeError = Color(rgb: 0x9F0909)

    // Adaptive semantic (values from the RN app's light/dark themes)
    static let biingeBackground = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let biingeCard = adaptive(light: 0xFAFAFA, dark: 0x181818)
    static let biingeSecondaryCard = adaptive(light: 0xEAEAEA, dark: 0x282828)
    static let biingeText = adaptive(light: 0x181818, dark: 0xFAFAFA)
    static let biingeTextSecondary = adaptive(light: 0x2B2835, dark: 0xD4D7CA)
    static let biingeBorder = adaptive(light: 0xD1CECF, dark: 0x2E3130)

    // Grays
    static let biingeGray = Color(rgb: 0xB5B5B5)
    static let biingeGrayDark = Color(rgb: 0x6E6969)
    static let biingeSpanishGray = Color(rgb: 0x999999)
}
