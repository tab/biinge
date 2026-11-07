import Foundation

/// The subtitle size the viewer picks, kept in user defaults on this device
enum SubtitleSize: String, CaseIterable {
    case small, medium, large

    static let key = "subtitleSize"

    var scale: Double {
        switch self {
        case .small: 0.8
        case .medium: 1
        case .large: 1.3
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

/// The subtitle weight the viewer picks, kept in user defaults on this device
enum SubtitleWeight: String, CaseIterable {
    case regular, bold

    static let key = "subtitleWeight"

    var label: String {
        rawValue.capitalized
    }
}

/// What sits behind the subtitle line, kept in user defaults on this device
enum SubtitleBackground: String, CaseIterable {
    case none, shadow, box

    static let key = "subtitleBackground"

    var label: String {
        rawValue.capitalized
    }
}

/// The subtitle's height above the player's bottom edge, kept in user defaults on this device
enum SubtitleHeight {
    static let key = "subtitleHeight"
    static let standard = 0.08
    static let range = 0.03...0.3
}

/// The subtitle timing offset in seconds, kept in user defaults on this device (positive shows the lines later)
enum SubtitleTiming {
    static let key = "subtitleOffset"
    static let range = -5.0...5.0
    static let step = 0.5

    /// "In sync" without an offset, otherwise how far the lines move, such as "1.5 s earlier"
    static func label(_ offset: Double) -> String {
        guard offset != 0 else { return "In sync" }
        return abs(offset).formatted(.number.precision(.fractionLength(1))) + " s " + (offset < 0 ? "earlier" : "later")
    }
}
