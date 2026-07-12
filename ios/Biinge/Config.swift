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
}
