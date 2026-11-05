/// The origin each screen of a section's navigation stack grew from, by the depth it sits at, so each pop finds its own screen's (generic so the tests build it without the Mac shell)
struct StackOrigins<Section: Hashable, Origin> {
    private var origins: [Section: [Int: Origin]] = [:]

    /// Saves the origin of the screen at this depth of the section's stack (depth 1 is the first pushed screen)
    mutating func save(_ origin: Origin, section: Section, depth: Int) {
        origins[section, default: [:]][depth] = origin
    }

    /// Drops the origins of the screens a pop of the section's stack from one depth to a lower one removed, returning the top screen's
    mutating func pop(section: Section, from depth: Int, to newDepth: Int) -> Origin? {
        let top = origins[section]?[depth]
        origins[section] = origins[section]?.filter { $0.key <= newDepth }
        return top
    }
}
