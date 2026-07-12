import SwiftUI

/// The authenticated shell: a four-tab layout matching the RN app. Movies, TV,
/// and Search are placeholders until Phases 4-6; Profile is functional.
struct RootView: View {
    let authManager: AuthManager
    let apiClient: APIClient

    var body: some View {
        TabView {
            Tab("Movies", systemImage: "film") {
                ComingSoonView(title: "Movies")
            }
            Tab("TV", systemImage: "tv") {
                ComingSoonView(title: "TV Shows")
            }
            Tab("Search", systemImage: "magnifyingglass") {
                ComingSoonView(title: "Search")
            }
            Tab("Profile", systemImage: "person.crop.circle") {
                ProfileView(authManager: authManager)
            }
        }
        .tint(Color.biingePrimary)
    }
}

private struct ComingSoonView: View {
    let title: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming soon",
                systemImage: "hourglass",
                description: Text("\(title) will live here.")
            )
            .navigationTitle(title)
        }
    }
}

private struct ProfileView: View {
    let authManager: AuthManager

    var body: some View {
        NavigationStack {
            List {
                if let user = authManager.user {
                    Section {
                        Text(user.email)
                            .font(.biingeCallout)
                        LabeledContent("Appearance", value: user.appearance.rawValue.capitalized)
                    }
                }
                Section {
                    Button("Log Out", role: .destructive) {
                        authManager.logout()
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
