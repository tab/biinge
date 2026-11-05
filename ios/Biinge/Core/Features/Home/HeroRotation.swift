import Foundation

/// The Apple TV featured row's clock: the page turns every 9 s of running time, a pause holds the page's time, and a turn by hand starts it over
struct HeroRotation {
    /// The seconds of running time each featured page shows before the next
    static let interval: TimeInterval = 9

    /// The featured page on screen (clamp it to the featured row, which a reload can shorten)
    private(set) var index = 0
    /// When the page's time began, moved later by each pause so only running time counts
    private var start = Date.distantPast
    /// When the current pause began, nil while the clock runs (it starts paused, so the first page counts from the first resume)
    private var pausedAt: Date? = .distantPast

    /// The running seconds the page has shown at `now`
    func elapsed(at now: Date) -> TimeInterval {
        (pausedAt ?? now).timeIntervalSince(start)
    }

    /// Holds the page's time from `now` (a no-op while already paused)
    mutating func pause(at now: Date) {
        if pausedAt == nil { pausedAt = now }
    }

    /// Runs the page's time again from `now` (a no-op while already running)
    mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        start += now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    /// Turns to the page at `index` by hand and starts its 9 s over from `now` (from the pause's start while paused, so the resume counts from zero)
    mutating func turn(to index: Int, at now: Date) {
        self.index = index
        start = pausedAt ?? now
    }

    /// Turns to the next of `count` pages, wrapping after the last, once the page has run 9 s at `now` (one title never turns); returns whether it turned
    mutating func advance(count: Int, at now: Date) -> Bool {
        guard count > 1, elapsed(at: now) >= Self.interval else { return false }
        index = (min(index, count - 1) + 1) % count
        start = now
        return true
    }
}
