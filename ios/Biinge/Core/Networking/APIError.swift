import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case badRequest(String)
    case server(status: Int)
    case network
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .badRequest(let message):
            return message
        case .server(let status):
            return "The server returned an error (\(status))."
        case .network:
            return "Could not reach the server. Check your connection and try again."
        case .decoding:
            return "The server returned unexpected data."
        }
    }
}
