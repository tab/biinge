import Foundation

enum Config {
    /// Base URL of the biinge API: scheme env override, then Info.plist (from .env), then localhost
    static let baseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !configured.isEmpty,
           let url = URL(string: configured) {
            return url
        }
        // swiftlint:disable:next force_unwrapping
        return URL(string: "http://localhost:8080/api/v1")!
    }()

    /// Builds a TMDB image URL for a poster/still/profile path (public CDN, no token)
    static func tmdbImageURL(path: String, size: String = "w342") -> URL? {
        guard !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}
