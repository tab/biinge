import Foundation

enum Config {
    /// Base URL of the biinge API, including the `/api/v1` prefix and no trailing slash.
    /// Override at runtime with the `API_BASE_URL` scheme environment variable.
    static let baseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:8080/api/v1")!
    }()

    /// Builds a TMDB image URL for a poster/still/profile path (public CDN, no token).
    static func tmdbImageURL(path: String, size: String = "w342") -> URL? {
        guard !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}
