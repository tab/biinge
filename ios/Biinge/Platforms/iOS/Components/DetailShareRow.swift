import SwiftUI
import UIKit

/// The More sheet's Share row, which creates the title's share link with a spinner in the row, then opens the share sheet over the More sheet (a failure shows an alert and no share sheet)
struct DetailShareRow: View {
    let kind: DetailKind
    /// The title's TMDB or IGDB ID
    let id: Int
    /// Closes the More sheet once the share sheet closes
    let close: () -> Void
    @Environment(\.apiClient) private var apiClient
    @State private var request = ShareLinkRequest()

    var body: some View {
        let url: URL? = if case .ready(let url) = request.phase { url } else { nil }
        let failure: String? = if case .failed(let message) = request.phase { message } else { nil }
        DetailMenuButton(systemImage: "square.and.arrow.up", title: "Share", isLoading: request.phase == .creating) {
            guard let apiClient else { return }
            Task { await request.start(kind: kind, id: id, apiClient: apiClient) }
        }
        .background {
            ShareSheet(url: url) {
                request.reset()
                close()
            }
        }
        .alert("Can’t share", isPresented: Binding(get: { failure != nil }, set: { if !$0 { request.reset() } }), presenting: failure) { _ in
        } message: { failure in
            Text(failure)
        }
    }
}

/// An empty view that presents the system share sheet for `url` while it is set, and calls `close` once the sheet closes
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL?
    let close: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        // a share sheet already up for this link stays as it is
        guard let url, controller.presentedViewController == nil else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in close() }
        sheet.popoverPresentationController?.sourceView = controller.view
        controller.present(sheet, animated: true)
    }
}
