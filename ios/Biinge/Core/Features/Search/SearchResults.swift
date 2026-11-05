import Foundation

/// One Search or Trending load's four lists (nil for a list whose request failed)
struct SearchResults {
    /// The trimmed query the lists answer, empty for Trending
    var term = ""
    var movies: [SearchMovie]? = []
    var series: [SearchSeries]? = []
    var games: [SearchGame]? = []
    var people: [SearchPerson]? = []

    /// Whether any of the four requests failed
    var failed: Bool { movies == nil || series == nil || games == nil || people == nil }

    /// Whether no list holds a result (a failed list counts as empty)
    var isEmpty: Bool {
        (movies ?? []).isEmpty && (series ?? []).isEmpty && (games ?? []).isEmpty && (people ?? []).isEmpty
    }
}
