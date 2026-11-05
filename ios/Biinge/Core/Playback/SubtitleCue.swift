import Foundation

/// One timed subtitle line from a WebVTT or SRT file, in seconds of the source
struct SubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String

    /// The cues of a WebVTT or SRT file in start order, with markup removed and empty cues dropped
    static func parse(_ file: String) -> [SubtitleCue] {
        let blocks = file
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        return blocks.compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            // the timing line may carry cue settings after the end time, such as "position:20%"
            let times = lines[timing].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard times.count == 2,
                  let start = seconds(times[0]),
                  let end = seconds(String(times[1].prefix { !$0.isWhitespace })) else { return nil }
            // shortcut: ASS drawing commands converted to text show as plain lines; filter them if a library needs it
            let text = lines[(timing + 1)...]
                .map { $0.replacingOccurrences(of: #"<[^>]*>|\{[^}]*\}"#, with: "", options: .regularExpression) }
                .map(decodeEntities)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return text.isEmpty ? nil : SubtitleCue(start: start, end: end, text: text)
        }
        .sorted { $0.start < $1.start }
    }

    /// The text showing at a time with every cue moved by offset seconds (positive shows them later), overlapping cues joined line by line (nil between cues)
    static func text(at time: Double, in cues: [SubtitleCue], offset: Double = 0) -> String? {
        let time = time - offset
        let showing = cues.filter { $0.start <= time && time < $0.end }.map(\.text)
        return showing.isEmpty ? nil : showing.joined(separator: "\n")
    }

    /// The text with WebVTT's character references decoded (&amp; last, so "&amp;lt;" stays "&lt;")
    private static func decodeEntities(_ line: String) -> String {
        line.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Seconds from "hh:mm:ss.mmm" or "mm:ss.mmm", with a comma or a dot before the milliseconds
    private static func seconds(_ stamp: String) -> Double? {
        let parts = stamp.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}
