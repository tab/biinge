import SwiftUI

/// Type scale built on Dynamic Type text styles, so every size follows the user's text setting
extension Font {
    static let biingeTitle1 = Font.system(.title, weight: .bold)
    static let biingeTitle2 = Font.system(.title2)
    static let biingeTitle3 = Font.system(.title3)
    static let biingeCallout = Font.system(.title3, weight: .semibold)
    static let biingeBody = Font.system(.title3, weight: .light)
    static let biingeHeadline = Font.system(.headline)
    static let biingeSubhead = Font.system(.body, weight: .bold)
    static let biingeFootnote = Font.system(.subheadline)
    static let biingeCaption1 = Font.system(.callout, weight: .bold)
    static let biingeCaption2 = Font.system(.callout, weight: .semibold)
}
