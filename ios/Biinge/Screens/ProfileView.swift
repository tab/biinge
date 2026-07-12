import SwiftUI

struct ProfileView: View {
    let authManager: AuthManager

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
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("Statistics", systemImage: "chart.pie")
                    }
                    NavigationLink {
                        AppearanceView(authManager: authManager)
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                }

                Section {
                    NavigationLink {
                        InfoView(title: "About", message: Self.aboutText)
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    NavigationLink {
                        InfoView(title: "Privacy", message: Self.privacyText)
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        InfoView(title: "Terms", message: Self.termsText)
                    } label: {
                        Label("Terms", systemImage: "doc.text")
                    }
                }

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
                }
            }
            .navigationTitle("Profile")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static let aboutText = "Biinge helps you track the movies and TV shows you want to watch, are watching, and have watched."
    static let privacyText = "Your library is stored on the biinge server and never shared. Poster and detail imagery is provided by TMDB."
    static let termsText = "Biinge is provided as-is for personal use. Movie and TV metadata is provided by TMDB and remains their property."
}

struct StatisticsView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var stats: AccountStats?

    var body: some View {
        List {
            if let stats {
                Section("Movies") {
                    LabeledContent("Want", value: "\(stats.movies.want)")
                    LabeledContent("Watched", value: "\(stats.movies.watched)")
                    LabeledContent("Watch time", value: formatMinutes(stats.movies.minutes))
                }
                Section("TV Shows") {
                    LabeledContent("Want", value: "\(stats.series.want)")
                    LabeledContent("Watching", value: "\(stats.series.watching)")
                    LabeledContent("Watched", value: "\(stats.series.watched)")
                }
                Section("Episodes") {
                    LabeledContent("Watched", value: "\(stats.episodes.watched)")
                    LabeledContent("Watch time", value: formatMinutes(stats.episodes.minutes))
                }
            } else {
                ProgressView().tint(Color.biingePrimary)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Statistics")
        .task { stats = try? await apiClient?.stats() }
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
        List {
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
                }
            }
        }
        .navigationTitle("Appearance")
    }
}

struct InfoView: View {
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            Text(message)
                .font(.biingeBody)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.biingeBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
