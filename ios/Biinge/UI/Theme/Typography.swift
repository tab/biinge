import SwiftUI

/// Type scale built on Dynamic Type text styles, so every size follows the user's text setting
extension Font {
    // Archivo (the bundled variable font's SemiBold instance) for titles and section headers, the system font for the rest
    /// A list screen's large title
    static let biingeLargeTitle = Font.custom("Archivo-SemiBold", size: 34, relativeTo: .largeTitle)
    /// A detail or sheet title
    static let biingeTitle1 = Font.custom("Archivo-SemiBold", size: 28, relativeTo: .title)
    static let biingeTitle2 = Font.system(.title2)
    static let biingeTitle3 = Font.system(.title3)
    static let biingeCallout = Font.system(.title3, weight: .semibold)
    static let biingeBody = Font.system(.title3, weight: .light)
    static let biingeHeadline = Font.system(.headline)
    /// A section header
    static let biingeSubhead = Font.custom("Archivo-SemiBold", size: 21, relativeTo: .title3)
    static let biingeFootnote = Font.system(.subheadline)
    static let biingeCaption1 = Font.system(.callout, weight: .bold)
    static let biingeCaption2 = Font.system(.callout, weight: .semibold)
}
