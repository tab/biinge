import SwiftUI

struct ProfileView: View {
    let authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var sheet: ProfileSheet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Avatar(email: authManager.user?.email ?? "", size: 60)
                        Text(authManager.user?.email ?? "")
                            .font(.biingeCallout)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        sheet = .statistics
                    } label: {
                        Label("Statistics", systemImage: "chart.pie")
                    }
                    Button {
                        sheet = .appearance
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                }
                .foregroundStyle(.primary)

                Section {
                    Button {
                        sheet = .info(InfoItem(title: "About", sections: Self.about))
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    Button {
                        sheet = .info(InfoItem(title: "Privacy", sections: Self.privacy))
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    Button {
                        sheet = .info(InfoItem(title: "Terms", sections: Self.terms))
                    } label: {
                        Label("Terms", systemImage: "doc.text")
                    }
                }
                .foregroundStyle(.primary)

                Section {
                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        Text("Log Out")
                    }
                }

                Section {
                    Text("Version \(appVersion)")
                        .font(.biingeFootnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Profile")
            .sheet(item: $sheet) { route in
                Group {
                    switch route {
                    case .statistics:
                        StatisticsView()
                    case .appearance:
                        AppearanceView(authManager: authManager)
                    case .info(let item):
                        InfoView(title: item.title, sections: item.sections)
                    }
                }
                .preferredColorScheme(colorScheme)
                .presentationDragIndicator(.hidden)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static let about: [InfoSection] = [
        InfoSection(heading: nil, body: "Biinge helps you track the movies and TV shows you want to watch, are watching, "
            + "and have watched — with your personal library synced across your devices."),
        InfoSection(heading: nil, body: "Film and TV metadata and imagery are provided by The Movie Database (TMDB)."),
    ]

    static let privacy: [InfoSection] = [
        InfoSection(heading: nil, body: "This policy explains what Biinge stores and how it is used. Biinge is a personal "
            + "watch-tracking app — it does not sell your data or show ads."),
        InfoSection(heading: "Information we store", body: "Your account details (email address and name), your appearance "
            + "preference, and the movies, TV shows, and episodes you track together with their watched state."),
        InfoSection(heading: "How it is used", body: "Your data is used only to run the app — to sync your library and show "
            + "your statistics. It is never sold, rented, or shared with advertisers."),
        InfoSection(heading: "Third-party services", body: "Biinge fetches film and TV metadata and imagery from The Movie "
            + "Database (TMDB). Anonymized crash and performance diagnostics may be collected to keep the app stable. "
            + "Your library is never shared with these services."),
        InfoSection(heading: "Data retention", body: "Your data is kept while your account is active. You can request "
            + "deletion of your account and its associated data at any time."),
    ]

    static let terms: [InfoSection] = [
        InfoSection(heading: nil, body: "By using Biinge you agree to these terms. Biinge is provided for personal, "
            + "non-commercial use."),
        InfoSection(heading: "Your account", body: "You are responsible for activity under your account and for keeping your "
            + "credentials secure. Do not misuse the service or attempt to disrupt it."),
        InfoSection(heading: "Content and attribution", body: "Film and TV metadata and imagery are provided by The Movie "
            + "Database (TMDB) and remain the property of their respective owners. This product uses the TMDB API but "
            + "is not endorsed or certified by TMDB."),
        InfoSection(heading: "Availability", body: "Biinge is provided \"as is\" and \"as available\", without warranties of "
            + "any kind. Features may change and the service may be unavailable from time to time."),
        InfoSection(heading: "Changes", body: "These terms may be updated over time. Continued use of Biinge means you accept "
            + "the current version."),
    ]
}

/// The Profile sub-screens, each presented as a detail-style modal
private enum ProfileSheet: Identifiable {
    case statistics
    case appearance
    case info(InfoItem)

    var id: String {
        switch self {
        case .statistics: return "statistics"
        case .appearance: return "appearance"
        case .info(let item): return item.id
        }
    }
}

/// Shared chrome for Profile modals: dark backdrop, translucent close button, rounded-top card
struct ModalScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.biingeCard.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title)
                        .font(.biingeTitle1)
                        .foregroundStyle(.primary)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            closeButton
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Close")
        .padding(.leading, 16)
        .padding(.top, 16)
    }
}

struct StatisticsView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var stats: AccountStats?

    var body: some View {
        ModalScaffold(title: "Statistics") {
            if let stats {
                statGroup("Movies", [
                    ("Want", "\(stats.movies.want)"),
                    ("Watched", "\(stats.movies.watched)"),
                    ("Watch time", formatMinutes(stats.movies.minutes)),
                ])
                statGroup("TV Shows", [
                    ("Want", "\(stats.series.want)"),
                    ("Watching", "\(stats.series.watching)"),
                    ("Watched", "\(stats.series.watched)"),
                ])
                statGroup("Episodes", [
                    ("Watched", "\(stats.episodes.watched)"),
                    ("Watch time", formatMinutes(stats.episodes.minutes)),
                ])
            } else {
                ProgressView().tint(Color.biingeLoader)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
        }
        .task { stats = try? await apiClient?.stats() }
    }

    private func statGroup(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray)
            ForEach(rows, id: \.0) { label, value in
                HStack {
                    Text(label).foregroundStyle(.primary)
                    Spacer()
                    Text(value).foregroundStyle(.secondary)
                }
                .font(.biingeCallout)
            }
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        if weeks > 0 { return "\(weeks)w \(days % 7)d \(hours % 24)h" }
        if days > 0 { return "\(days)d \(hours % 24)h" }
        return "\(hours)h"
    }
}

struct AppearanceView: View {
    let authManager: AuthManager
    @Environment(\.apiClient) private var apiClient

    var body: some View {
        ModalScaffold(title: "Appearance") {
            VStack(spacing: 0) {
                ForEach(Appearance.allCases, id: \.self) { option in
                    Button {
                        guard let apiClient else { return }
                        Task { await authManager.updateAppearance(option, using: apiClient) }
                    } label: {
                        HStack {
                            Text(option.rawValue.capitalized).foregroundStyle(.primary)
                            Spacer()
                            if authManager.user?.appearance == option {
                                Image(systemName: "checkmark").foregroundStyle(Color.biingePrimary)
                            }
                        }
                        .font(.biingeCallout)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option != Appearance.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }
}

/// One block of an info page, with an optional heading
struct InfoSection {
    let heading: String?
    let body: String
}

/// A titled info page presented as a modal sheet (About, Privacy, Terms)
struct InfoItem: Identifiable {
    var id: String { title }
    let title: String
    let sections: [InfoSection]
}

struct InfoView: View {
    let title: String
    let sections: [InfoSection]

    var body: some View {
        ModalScaffold(title: title) {
            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]
                VStack(alignment: .leading, spacing: 8) {
                    if let heading = section.heading {
                        Text(heading)
                            .font(.biingeSubhead)
                            .foregroundStyle(Color.biingeGraniteGray)
                    }
                    Text(section.body)
                        .font(.biingeBody)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
