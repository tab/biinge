import CoreGraphics
import Foundation

/// The player bars' rules: when they show, how times read, which quality badges the stream earns and the speed menu's rates
enum PlayerChrome {
    /// Seconds without input before the bars and pointer hide while playback runs
    static let idle: TimeInterval = 3

    /// The bars show unless playback runs, and then while loading, while a menu is open or a drag held, and until idle seconds after the last input
    static func isVisible(isPlaying: Bool, isLoading: Bool, isHeld: Bool, lastInput: Date, now: Date) -> Bool {
        !isPlaying || isLoading || isHeld || now.timeIntervalSince(lastInput) < idle
    }

    /// "1:02:05" from an hour on, "4:05" below it (a non-finite or negative time reads as zero)
    static func clock(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// "4K", "1080p" or "720p" from the video size, then "5.1" or "7.1" from the audio's channel count
    static func badges(videoSize: CGSize, audioChannels: Int?) -> [String] {
        var badges: [String] = []
        // widths cover letterboxed sources, whose height falls short of the class
        if videoSize.width >= 3200 || videoSize.height >= 2000 {
            badges.append("4K")
        } else if videoSize.width >= 1800 || videoSize.height >= 1000 {
            badges.append("1080p")
        } else if videoSize.width >= 1200 || videoSize.height >= 700 {
            badges.append("720p")
        }
        switch audioChannels {
        case 6: badges.append("5.1")
        case 8: badges.append("7.1")
        default: break
        }
        return badges
    }

    /// The speed menu's rates, slowest first
    static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
}
