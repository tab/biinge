import JellyfinAPI
import SwiftUI

/// A titled row of details cards that scrolls sideways with focus and brightens its title while one of its cards has focus
struct TVDetailsRow<Item, Card: View>: View {
    let title: String
    /// The number shown after the title, nil for none
    var count: Int?
    let spacing: CGFloat
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    /// The focused card's position, nil while focus sits outside the row
    @FocusState private var focused: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(focused != nil ? Color.biingeTextFocused : Color.biingeText.opacity(0.7))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 29))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                }
            }
            .padding(.leading, 96)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    // one person can hold two roles, and a person two credits on one title, so the position is the identity
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        card(item)
                            .focused($focused, equals: index)
                    }
                }
                .padding(.horizontal, 96)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// The Recommendations row of a details screen, marking the titles the library holds
struct TVRecommendationsRow: View {
    let items: [Recommendation]
    /// The library state of a title by its ID
    let state: @MainActor (Int) -> WatchState?
    let poster: (Recommendation) -> URL?
    let route: (Recommendation) -> TVRoute

    var body: some View {
        TVDetailsRow(title: "Recommendations", spacing: 48, items: items) { item in
            NavigationLink(value: route(item)) {
                PosterImage(title: item.title, cornerRadius: 0, poster: poster(item),
                            frame: CGSize(width: 260, height: 390), titleFont: .system(size: 26), titlePadding: 20)
                    .overlay(alignment: .topLeading) {
                        if state(item.id) != nil { WatchedBadge() }
                    }
            }
            .buttonStyle(TVCardButtonStyle(width: 260, height: 390, cornerRadius: 16, title: item.title, subtitle: nil))
        }
    }
}

/// A movie's or series' rows: Cast & Crew from the biinge credits, Recommendations, then More in Your Library from the items Jellyfin finds similar, each hidden when empty
struct TVDetailsRows: View {
    let connection: JellyfinConnection
    /// The Jellyfin movie or series the similar items are like (nil when the library holds none)
    let itemID: String?
    let credits: [CreditPerson]
    let recommendations: TVRecommendationsRow

    /// Empty until the similar items land, and when Jellyfin finds none or the load fails
    @State private var similar: [BaseItemDto] = []

    var body: some View {
        let cast = Array(credits.prefix(20))
        VStack(alignment: .leading, spacing: 72) {
            if !cast.isEmpty {
                TVDetailsRow(title: "Cast & Crew", spacing: 44, items: cast) { person in
                    let name = person.name
                    let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
                    // a person without a portrait shows the initials
                    let photo = Config.tmdbImageURL(path: person.profilePath, size: "w185")
                    NavigationLink(value: TVRoute.person(id: person.id)) {
                        // black-and-white portraits, as on iPhone (the placeholder is already grey)
                        PosterImage(title: initials, cornerRadius: 0, poster: photo, frame: CGSize(width: 160, height: 160), titleFont: .system(size: 26), titlePadding: 20)
                            .grayscale(1)
                    }
                    .buttonStyle(TVCardButtonStyle(width: 180, height: 160, cornerRadius: 80, title: name, subtitle: person.description))
                }
            }
            if !recommendations.items.isEmpty {
                recommendations
            }
            if !similar.isEmpty {
                TVDetailsRow(title: "More in Your Library", spacing: 48, items: similar) { item in
                    TVPosterCard(connection: connection, item: item)
                }
            }
        }
        // back from the player, once its stop report has gone out, the posters show the new progress
        .task(id: "\(itemID ?? "")-\(connection.playbackEnded)") { await load() }
    }

    /// Loads the similar items; a revoked token disconnects, and any other failure hides the row
    private func load() async {
        guard let service = connection.service, let itemID else {
            similar = []
            return
        }
        do {
            similar = try await service.similar(itemID: itemID, limit: 12)
        } catch {
            // leaving the screen cancels the load, which is no failure
            guard !Task.isCancelled else { return }
            if await connection.handleFailure(error) { return }
            similar = []
        }
    }
}
