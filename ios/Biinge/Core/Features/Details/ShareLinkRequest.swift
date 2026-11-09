import Foundation
import Observation

/// A title's share link as the details screens create it: the Share row starts it, the share sheet opens once it is ready, and an error shows when it failed
@MainActor
@Observable
final class ShareLinkRequest {
    /// Where the share link stands
    enum Phase: Equatable {
        case idle
        case creating
        /// Created, with the link the share sheet opens
        case ready(URL)
        /// The request failed, with the error's message (no share sheet opens)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// Creates the title's share link (a second tap while one is being created does nothing)
    func start(kind: DetailKind, id: Int, apiClient: APIClient) async {
        guard phase != .creating else { return }
        phase = .creating
        // the API names a series tv
        let type = switch kind {
        case .movie: "movie"
        case .series: "tv"
        case .game: "game"
        }
        do {
            phase = .ready(try await apiClient.createShare(CreateShareBody(type: type, objectID: id)).url)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Returns to idle once the share sheet or the error closes
    func reset() {
        phase = .idle
    }
}
