import JellyfinAPI
import SwiftUI

/// The details screens' facts, the Cast & Crew row from the biinge credits, the More in Your Library row of the items Jellyfin finds similar, then the Recommendations row, each hidden when empty
struct DetailsRows: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// The Jellyfin movie or series the similar items are like (nil when the library holds none)
    let itemID: String?
    let credits: [CreditPerson]
    let facts: [DetailFact]
    let recommendations: RecommendationsRow

    /// Empty until the similar items land, and when Jellyfin finds none or the load fails
    @State private var similar: [BaseItemDto] = []

    var body: some View {
        let cast = Array(credits.prefix(20))
        VStack(alignment: .leading, spacing: 44) {
            DesktopDetailFacts(facts: facts)
                .padding(.horizontal, 40)
            if !cast.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Cast & Crew")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .padding(.horizontal, 40)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 18) {
                            // one person can hold two roles, so the position is the identity
                            ForEach(Array(cast.enumerated()), id: \.offset) { _, person in
                                let name = person.name
                                let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
                                // a person without a portrait shows the initials
                                let photo = Config.tmdbImageURL(path: person.profilePath, size: "w185")
                                let role = person.description
                                NavigationLink(value: DesktopRoute.person(id: person.id)) {
                                    VStack(spacing: 10) {
                                        // greyscale, as the iPhone's cast row
                                        CachedImage(url: photo, maxPixel: 176, grayscale: true) {
                                            ZStack {
                                                Color.biingeSecondaryCard
                                                Text(initials)
                                                    .font(.system(size: 24, weight: .semibold))
                                                    .foregroundStyle(Color.biingeGrayDark)
                                            }
                                        }
                                        .frame(width: 88, height: 88)
                                        .clipShape(Circle())
                                        VStack(spacing: 2) {
                                            Text(name)
                                                .font(.system(size: 14.5, weight: .semibold))
                                            Text(role)
                                                .font(.system(size: 13.5))
                                                .foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1)
                                    }
                                    .frame(width: 112)
                                    .contentShape(Rectangle())
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            if !similar.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    Text("More in Your Library")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .padding(.horizontal, 40)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 18) {
                            ForEach(similar, id: \.id) { item in
                                DesktopPosterCard(connection: connection, apiClient: apiClient, item: item)
                                    .frame(width: 164)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 40)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
            if !recommendations.items.isEmpty {
                recommendations
            }
        }
        .padding(.bottom, facts.isEmpty && cast.isEmpty && similar.isEmpty && recommendations.items.isEmpty ? 0 : 80)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: itemID) { await load() }
        // back from the player, once its stop report has gone out, the posters show the new progress
        .onChange(of: connection.playbackEnded) {
            Task { await load() }
        }
    }

    /// Loads the similar items; a revoked token disconnects, and any other failure hides the row
    private func load() async {
        guard let service = connection.service, let itemID else { return }
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
