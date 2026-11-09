import AppKit
import SwiftUI

/// The details screens' More button, a menu with Start Over, Mark Season Watched and Share (the share picker opens under the button once the link is ready, and a failure shows an alert)
struct MoreMenu: View {
    let kind: DetailKind
    /// The title's TMDB or IGDB ID
    let id: Int
    let apiClient: APIClient
    /// The Start Over entry's label and its play from zero, nil without a stored position
    let startOver: (label: String, play: () -> Void)?
    /// The Mark Season Watched entry's season number and its write, nil when there's no season to mark
    let markSeason: (number: Int, mark: () -> Void)?
    @State private var share = ShareLinkRequest()

    var body: some View {
        let url: URL? = if case .ready(let url) = share.phase { url } else { nil }
        let failure: String? = if case .failed(let message) = share.phase { message } else { nil }
        Menu {
            if let startOver {
                Button(startOver.label, action: startOver.play)
            }
            if let markSeason {
                Button("Mark Season \(markSeason.number) Watched", action: markSeason.mark)
            }
            Button("Share…") { Task { await share.start(kind: kind, id: id, apiClient: apiClient) } }
        } label: {
            // the spinner stands in for the ellipsis while the link is being created
            Group {
                if share.phase == .creating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .medium))
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.biingeText.opacity(0.14), in: Circle())
            .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
        .background { SharePicker(url: url) { share.reset() } }
        .alert("Can’t share", isPresented: Binding(get: { failure != nil }, set: { if !$0 { share.reset() } }), presenting: failure) { _ in
        } message: { failure in
            Text(failure)
        }
    }
}

/// An empty view that shows the system share picker for `url` under itself while it is set, and calls `close` once the picker closes
private struct SharePicker: NSViewRepresentable {
    let url: URL?
    let close: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.close = close
        // a picker already up for this link stays as it is
        guard let url, context.coordinator.picker == nil else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = context.coordinator
        context.coordinator.picker = picker
        // outside the view update, so the picker's close never changes state mid-update
        Task { picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
    }

    /// Keeps the open picker alive and hands back its close
    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var picker: NSSharingServicePicker?
        var close: () -> Void = {}

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            picker = nil
            close()
        }
    }
}
