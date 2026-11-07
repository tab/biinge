import SwiftUI

struct ProfileView: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let connection: JellyfinConnection
    /// Set from another tab to open the Jellyfin sheet, and cleared once it opens
    @Binding var opensJellyfin: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var sheet: ProfileSheet?

    var body: some View {
        let email = authManager.user?.email ?? ""
        // the first name, else the email's local part
        let name = authManager.user?.firstName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(email.prefix { $0 != "@" })
        let separator = Rectangle().fill(Color.biingeFill(0.06)).frame(height: 1)

        ScrollView {
            VStack(spacing: 16) {
                Text("Profile")
                    .font(.biingeLargeTitle)
                    .tracking(-1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Text(name.prefix(1).uppercased())
                            .font(.custom("Archivo-SemiBold", size: 28, relativeTo: .title))
                            .frame(width: 66, height: 66)
                            .background(Color.biingeFill(0.1), in: Circle())
                            .overlay(Circle().strokeBorder(Color.biingeFill(0.1), lineWidth: 1))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(.custom("Archivo-SemiBold", size: 24, relativeTo: .title2))
                                .tracking(-0.6)
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(Color.biingeTextSecondary)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(18)

                    separator

                    // one target for the whole row: it opens the connection, or the connect form while not connected
                    Button {
                        sheet = .jellyfin
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.body)
                                .foregroundStyle(Color.biingeText.opacity(0.8))
                                .frame(width: 36, height: 36)
                                .background(Color.biingeFill(0.08), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .bottomTrailing) {
                                    // green while this iPhone holds a Jellyfin session, ringed in the card's colour
                                    Circle()
                                        .fill(connection.isConnected ? Color.biingeWatched : Color.biingeTextTertiary)
                                        .frame(width: 11, height: 11)
                                        .background(Color.biingeFill(0.05), in: Circle().inset(by: -2))
                                        .background(Color.biingeBackground, in: Circle().inset(by: -2))
                                        .offset(x: 2, y: 2)
                                }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(connection.serverName ?? "Jellyfin")
                                    .font(.callout.weight(.semibold))
                                Text(connection.isConnected ? "Jellyfin · Connected" : "Not connected")
                                    .font(.footnote)
                                    .foregroundStyle(Color.biingeText.opacity(0.55))
                            }
                            Spacer(minLength: 0)
                            if connection.isConnected {
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.biingeTextTertiary)
                            } else {
                                Text("Connect")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.biingeBackground)
                                    .padding(.horizontal, 16)
                                    .frame(height: 36)
                                    .background(Color.biingeText, in: Capsule())
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 14)
                        .frame(minHeight: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
                .foregroundStyle(Color.biingeText)
                .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.biingeFill(0.06), lineWidth: 1))

                VStack(spacing: 0) {
                    menuRow("Statistics", symbol: "chart.bar") { sheet = .statistics }
                    separator
                    menuRow("Appearance", symbol: "circle.lefthalf.filled", value: authManager.user?.appearance.rawValue.capitalized) {
                        sheet = .appearance
                    }
                    separator
                    menuRow("About Biinge", symbol: "info.circle") {
                        sheet = .info(InfoItem(title: "About", sections: Self.about))
                    }
                    separator
                    menuRow("Privacy", symbol: "hand.raised") {
                        sheet = .info(InfoItem(title: "Privacy", sections: Self.privacy))
                    }
                    separator
                    menuRow("Terms", symbol: "doc.text") {
                        sheet = .info(InfoItem(title: "Terms", sections: Self.terms))
                    }
                }
                .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.biingeFill(0.06), lineWidth: 1))

                Button(role: .destructive) {
                    authManager.logout()
                } label: {
                    Text("Log Out")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.biingeError)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.biingeFill(0.06), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.pressable)

                Text("Biinge \(appVersion)")
                    .font(.footnote)
                    .foregroundStyle(Color.biingeTextTertiary)
            }
            .padding(16)
        }
        .background(Color.biingeBackground)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["DEBUG_STATISTICS"] == "1" {
                sheet = .statistics
            }
            #endif
        }
        .onChange(of: opensJellyfin, initial: true) { _, opens in
            guard opens else { return }
            opensJellyfin = false
            sheet = .jellyfin
        }
        .sheet(item: $sheet) { route in
            Group {
                switch route {
                case .statistics:
                    MobileStatisticsView()
                case .appearance:
                    AppearanceView(authManager: authManager)
                case .jellyfin:
                    JellyfinConnectionView(connection: connection, apiClient: apiClient, authManager: authManager)
                case .info(let item):
                    InfoView(title: item.title, sections: item.sections)
                }
            }
            .preferredColorScheme(colorScheme)
            .presentationDragIndicator(.hidden)
        }
    }

    /// A menu card row (the trailing value is Appearance's current choice)
    private func menuRow(_ title: String, symbol: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.biingeText.opacity(0.8))
                    .frame(width: 24)
                Text(title)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Color.biingeTextSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.biingeTextTertiary)
            }
            .foregroundStyle(Color.biingeText)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static let about: [InfoSection] = [
        InfoSection(heading: nil, body: "Biinge helps you track the films, TV shows and games you mean to get to, the ones "
            + "you're part-way through, and the ones you've finished — with your personal library synced across your devices."),
        InfoSection(heading: nil, body: "Film and TV metadata and imagery are provided by The Movie Database (TMDB). "
            + "Game metadata and imagery are provided by IGDB."),
    ]

    static let privacy: [InfoSection] = [
        InfoSection(heading: nil, body: "This policy explains what Biinge stores and how it is used. Biinge is a personal "
            + "watch-tracking app — it does not sell your data or show ads."),
        InfoSection(heading: "Information we store", body: "Your account details (email address and name), your appearance "
            + "preference, and the films, TV shows, episodes and games you track together with their state."),
        InfoSection(heading: "How it is used", body: "Your data is used only to run the app — to sync your library and show "
            + "your statistics. It is never sold, rented, or shared with advertisers."),
        InfoSection(heading: "Third-party services", body: "Biinge fetches film and TV metadata and imagery from The Movie "
            + "Database (TMDB), and game metadata and imagery from IGDB. Anonymized crash and performance diagnostics may "
            + "be collected to keep the app stable. Your library is never shared with these services."),
        InfoSection(heading: "Data retention", body: "Your data is kept while your account is active. You can request "
            + "deletion of your account and its associated data at any time."),
    ]

    static let terms: [InfoSection] = [
        InfoSection(heading: nil, body: "By using Biinge you agree to these terms. Biinge is provided for personal, "
            + "non-commercial use."),
        InfoSection(heading: "Your account", body: "You are responsible for activity under your account and for keeping your "
            + "credentials secure. Do not misuse the service or attempt to disrupt it."),
        InfoSection(heading: "Content and attribution", body: "Film and TV metadata and imagery are provided by The Movie "
            + "Database (TMDB), and game metadata and imagery by IGDB. Both remain the property of their respective "
            + "owners. This product uses the TMDB and IGDB APIs but is not endorsed or certified by either."),
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
    case jellyfin
    case info(InfoItem)

    var id: String {
        switch self {
        case .statistics: return "statistics"
        case .appearance: return "appearance"
        case .jellyfin: return "jellyfin"
        case .info(let item): return item.id
        }
    }
}

/// Shared chrome for Profile modals: the surface backdrop under a 38 pt rounded top, a 36 pt glass close button and an Archivo title (a pushed screen gets a back chevron instead)
struct ModalScaffold<Content: View>: View {
    let title: String
    var pushed = false
    /// The content's side padding (the title stays 20 pt from the edge either way)
    var inset: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.biingeSurface.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(title)
                        .font(.biingeLargeTitle)
                        .tracking(-1)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20 - inset)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset)
                // below the close button: its 36 pt circle sits 20 pt in, then a 14 pt gap
                .padding(.top, 70)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            CloseButton(back: pushed, size: 36)
        }
        .presentationCornerRadius(38)
    }
}

/// Profile → Appearance: a preview tile per theme that re-themes the app on tap and a sample of the library in it
struct AppearanceView: View {
    let authManager: AuthManager
    @Environment(\.apiClient) private var apiClient

    var body: some View {
        let current = authManager.user?.appearance ?? .system

        ModalScaffold(title: "Appearance") {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Appearance.allCases, id: \.self) { option in
                    let isSelected = option == current
                    Button {
                        guard let apiClient else { return }
                        Task { await authManager.updateAppearance(option, using: apiClient) }
                    } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                themeMock(dark: option != .light)
                                if option == .system {
                                    themeMock(dark: false).clipShape(TopLeadingHalf())
                                }
                            }
                            .frame(width: 88, height: 156)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay {
                                // the selected ring stands 3 pt off the tile, over the sheet's own colour
                                RoundedRectangle(cornerRadius: isSelected ? 23 : 19)
                                    .strokeBorder(isSelected ? Color.biingeText : Color.biingeFill(0.1), lineWidth: isSelected ? 2 : 1)
                                    .padding(isSelected ? -5 : -1)
                            }
                            VStack(spacing: 7) {
                                Text(option.rawValue.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.biingeBackground)
                                    .opacity(isSelected ? 1 : 0)
                                    .frame(width: 24, height: 24)
                                    .background(isSelected ? Color.biingeText : .clear, in: Circle())
                                    .overlay(Circle().strokeBorder(Color.biingeFill(isSelected ? 0 : 0.3), lineWidth: 1.5))
                            }
                        }
                        .foregroundStyle(Color.biingeText)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(option.rawValue.capitalized)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: current)

            VStack(alignment: .leading, spacing: 10) {
                Text("Preview")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.biingeTextSecondary)
                    .padding(.leading, 4)
                preview
            }

            Text("Posters, video and the player stay dark in every theme.")
                .font(.footnote)
                .foregroundStyle(Color.biingeTextTertiary)
                .padding(.horizontal, 4)
        }
    }

    /// A theme's miniature screen in its own fixed colours (a title bar, two chips, four posters and the tab bar)
    private func themeMock(dark: Bool) -> some View {
        let ink = dark ? Color(rgb: 0xF4F4F2) : Color(rgb: 0x16161A)
        return ZStack(alignment: .bottom) {
            Color(rgb: dark ? 0x101014 : 0xF3F3F1)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.85)).frame(width: 48, height: 7)
                HStack(spacing: 4) {
                    Capsule().fill(dark ? Color.white.opacity(0.22) : Color.black.opacity(0.2)).frame(width: 16, height: 6)
                    Capsule().fill(dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)).frame(width: 16, height: 6)
                }
                Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(0..<2, id: \.self) { column in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Self.posterTones[row * 2 + column].gradient)
                                    .aspectRatio(2 / 3, contentMode: .fit)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.horizontal, 9)
            Capsule()
                .fill(dark ? Color(rgb: 0x3C3C44).opacity(0.9) : Color.white.opacity(0.95))
                .overlay(Capsule().strokeBorder(Color.white.opacity(dark ? 0.12 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(dark ? 0 : 0.15), radius: 2, y: 1)
                .frame(height: 15)
                .padding(8)
        }
    }

    /// The sample library in the current theme: the filter pills, a part-watched film and its Resume row (static, no network)
    private var preview: some View {
        VStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(["Want", "Watched", "Library"], id: \.self) { pill in
                    Text(pill)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(pill == "Library" ? Color.biingeText : Color.biingeTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(pill == "Library" ? Color.biingeFill(0.14) : .clear, in: Capsule())
                }
            }
            .padding(3)
            .background(Color.biingeFill(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.biingeFill(0.06), lineWidth: 1))

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Self.posterTones[0].gradient)
                    .frame(width: 54, height: 81)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                VStack(alignment: .leading, spacing: 5) {
                    Text("La La Land")
                        .font(.custom("Archivo-SemiBold", size: 19, relativeTo: .headline))
                        .tracking(-0.4)
                    Text("2016 · 2h 8m · 1h 12m left")
                        .font(.footnote)
                        .foregroundStyle(Color.biingeTextSecondary)
                    Capsule()
                        .fill(Color.biingeFill(0.14))
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule().fill(Color.biingeText).frame(width: proxy.size.width * 0.44)
                            }
                        }
                        .frame(height: 4)
                }
            }

            HStack(spacing: 10) {
                Label("Resume", systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.biingeBackground)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.biingeText, in: Capsule())
                Image(systemName: "bookmark.fill")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .background(Color.biingeFill(0.14), in: Circle())
            }
        }
        .foregroundStyle(Color.biingeText)
        .padding(14)
        .background(Color.biingeBackground, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.biingeFill(0.06), lineWidth: 1))
        // sample content only, so VoiceOver skips it
        .accessibilityHidden(true)
    }

    /// Stand-in poster grays, dark in every theme like real artwork
    private static let posterTones = [Color(rgb: 0x3A3A40), Color(rgb: 0x5C5C63), Color(rgb: 0x2C2C31), Color(rgb: 0x4A4A50)]
}

/// The top-left half of a rectangle, cut corner to corner (the System tile's Light side)
private struct TopLeadingHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Profile → Jellyfin: the connect flow while this iPhone isn't connected, else the server, the Jellyfin user, Reconnect and Disconnect
struct JellyfinConnectionView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let authManager: AuthManager

    @State private var isConfirmingDisconnect = false

    var body: some View {
        // the server check's name, else the address's host (nil after a disconnect)
        let server = connection.serverName ?? connection.serverURL?.host() ?? "Jellyfin"
        ModalScaffold(title: connection.isConnected ? "Jellyfin" : "Connect Jellyfin") {
            if connection.isConnected {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .frame(width: 38, height: 38)
                            .background(Color.biingeFill(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.biingeWatched)
                                    .frame(width: 11, height: 11)
                                    .offset(x: 2, y: 2)
                            }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(server)
                                .font(.body.weight(.semibold))
                            Text("Connected")
                                .font(.subheadline)
                                .foregroundStyle(Color.biingeTextSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    Divider()
                    LabeledContent("Signed in as", value: connection.userName ?? "—")
                        .frame(minHeight: 50)
                        .padding(.horizontal, 14)
                    Divider()
                    LabeledContent("Server", value: connection.serverURL?.host() ?? "—")
                        .frame(minHeight: 50)
                        .padding(.horizontal, 14)
                    Divider()
                    LabeledContent("Biinge account", value: authManager.user?.email ?? "")
                        .frame(minHeight: 50)
                        .padding(.horizontal, 14)
                }
                .font(.subheadline)
                .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.biingeFill(0.06)))

                VStack(spacing: 0) {
                    // Reconnect ends only this device's session and keeps the user, so the connect form opens with it filled in
                    Button {
                        Task { await connection.reconnect() }
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    Divider()
                    Button {
                        isConfirmingDisconnect = true
                    } label: {
                        Label("Disconnect…", systemImage: "minus.circle")
                            .foregroundStyle(Color.biingeError)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
                .font(.body)
                .foregroundStyle(Color.biingeText)
                .buttonStyle(.pressable)
                .padding(.horizontal, 14)
                .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.biingeFill(0.06)))

                Text("Disconnecting keeps you logged in to Biinge. Your lists stay; Play and Library need Jellyfin.")
                    .font(.footnote)
                    .foregroundStyle(Color.biingeTextTertiary)
                    .padding(.horizontal, 4)
            } else {
                MobileConnectView(connection: connection, apiClient: apiClient)
            }
        }
        .confirmationDialog("Disconnect Jellyfin?", isPresented: $isConfirmingDisconnect, titleVisibility: .visible) {
            // the sheet turns to the connect form once the connection is gone
            Button("Disconnect", role: .destructive) {
                Task { await connection.disconnect(apiClient: apiClient) }
            }
        } message: {
            Text("This iPhone stops playing from \(server). You stay logged in to Biinge, and your lists stay.")
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
                            .foregroundStyle(Color.biingeTextSecondary)
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
