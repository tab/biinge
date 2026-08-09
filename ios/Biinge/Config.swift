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
        return URL(string: "http://localhost:8080/api/v1")!
    }()

    /// Sentry DSN: scheme env override, then Info.plist (from .env); nil when unset
    static let sentryDSN: String? = {
        if let override = ProcessInfo.processInfo.environment["SENTRY_DSN"], !override.isEmpty {
            return override
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String,
           !configured.isEmpty {
            return configured
        }
        return nil
    }()

    /// Whether crash and error reporting is on: env override, then Info.plist (from .env)
    static let sentryEnabled: Bool = {
        if let override = ProcessInfo.processInfo.environment["SENTRY_ENABLED"] {
            return boolValue(override)
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SENTRY_ENABLED") as? String {
            return boolValue(configured)
        }
        return false
    }()

    /// Builds a TMDB image URL for a poster/still/profile path (public CDN, no token)
    static func tmdbImageURL(path: String, size: String = "w342") -> URL? {
        guard !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    /// Builds an IGDB cover URL from a cover image_id (public CDN, no token)
    static func igdbImageURL(imageId: String, size: String = "cover_big_2x") -> URL? {
        guard !imageId.isEmpty else { return nil }
        return URL(string: "https://images.igdb.com/igdb/image/upload/t_\(size)/\(imageId).jpg")
    }

    private static func boolValue(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}
