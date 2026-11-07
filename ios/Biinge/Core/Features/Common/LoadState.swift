/// What an iPhone list or Library shows in place of its posters
enum LoadState: Equatable {
    case loading
    /// Loaded, with nothing to show
    case empty
    /// Jellyfin isn't connected on this device (the Library only)
    case notConnected
    /// The load failed, with the error's message
    case failed(String)

    /// A biinge list's state, nil while it has titles to show (a failed load shows its error, never the empty state)
    init?(hasLoaded: Bool, isEmpty: Bool, loadError: (any Error)?) {
        guard isEmpty else { return nil }
        if let loadError {
            self = .failed(loadError.localizedDescription)
        } else {
            self = hasLoaded ? .empty : .loading
        }
    }

    /// The Library's state from the connection and its grid's first page (total is nil until a page lands), nil once the grid has items (a failed load of an empty library shows its error, never the empty state)
    init?(isConnected: Bool, total: Int?, failure: String?) {
        guard isConnected else {
            self = .notConnected
            return
        }
        if let total, total > 0 { return nil }
        if let failure {
            self = .failed(failure)
        } else {
            self = total == nil ? .loading : .empty
        }
    }
}
