import JellyfinAPI

/// The mockup's duration: "2h 44m", or "47 min" under an hour
func duration(ticks: Int) -> String {
    let minutes = ticks / 600_000_000
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min"
}

/// An episode's "S2 · E1", or "E1" without a season number
func episodeCode(_ item: BaseItemDto) -> String {
    let episode = "E\(item.indexNumber ?? 0)"
    return item.parentIndexNumber.map { "S\($0) · \(episode)" } ?? episode
}
