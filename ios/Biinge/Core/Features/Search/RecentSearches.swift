import Foundation

/// The last distinct searches the user submitted or opened a result of, newest first (stored as a JSON array, so AppStorage can keep it)
struct RecentSearches: RawRepresentable, Equatable {
    /// The most terms the list keeps
    static let limit = 8
    /// The UserDefaults key the Mac and Apple TV search screens keep the list under
    static let storageKey = "recentSearches"

    private(set) var terms: [String]

    init(terms: [String] = []) {
        self.terms = terms
    }

    init?(rawValue: String) {
        // a value that doesn't decode starts the list empty rather than leaving AppStorage on its default forever
        terms = (try? JSONDecoder().decode([String].self, from: Data(rawValue.utf8))) ?? []
    }

    var rawValue: String {
        (try? JSONEncoder().encode(terms)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "[]"
    }

    /// Puts the trimmed term first, dropping an earlier copy that differs only in case and the oldest past the limit (a blank term changes nothing)
    mutating func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        terms.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        terms.insert(trimmed, at: 0)
        terms = Array(terms.prefix(Self.limit))
    }

    mutating func clear() {
        terms = []
    }
}
