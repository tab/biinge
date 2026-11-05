import JellyfinAPI
import SwiftUI

/// The details screens' More button, a menu with Start Over and Mark Season Watched (absent when it offers none)
struct MoreMenu: View {
    let connection: JellyfinConnection
    /// The Start Over entry's label and the item it plays from zero, nil without a stored position
    let startOver: (label: String, item: BaseItemDto)?
    /// The Mark Season Watched entry's season number and its write, nil when there's no season to mark
    let markSeason: (number: Int, mark: () -> Void)?

    var body: some View {
        // with nothing to offer, the button stays away instead of opening an empty menu
        if startOver != nil || markSeason != nil {
            Menu {
                if let startOver {
                    Button(startOver.label) { Task { await connection.play(startOver.item, fromStart: true) } }
                }
                if let markSeason {
                    Button("Mark Season \(markSeason.number) Watched", action: markSeason.mark)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
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
        }
    }
}
