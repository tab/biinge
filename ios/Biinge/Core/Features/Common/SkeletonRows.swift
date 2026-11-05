import Foundation

/// The skeleton row count of each list, as its last load returned it, kept in memory for the app's run
@MainActor
enum SkeletonRows {
    /// The last load's row count by list key, such as "episodes-1399-1" or "continue-watching"
    static var counts: [String: Int] = [:]

    /// How many skeleton rows the list at `key` shows: its last load's count up to `screenful`, and a screenful on a first visit
    static func count(for key: String, screenful: Int) -> Int {
        min(counts[key] ?? screenful, screenful)
    }
}
