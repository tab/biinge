import SwiftUI

/// Apple TV Settings: the server's state on the left, the account facts and Statistics, Connect, Reconnect, Disconnect and Log Out on the right, with a confirmation for Disconnect and Log Out
struct TVSettingsView: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let connection: JellyfinConnection

    private enum Confirmation {
        case disconnect, logOut
    }

    private enum ConfirmButton {
        case confirm, cancel
    }

    @State private var confirming: Confirmation?
    @FocusState private var confirmFocus: ConfirmButton?

    var body: some View {
        // the server check's name, else the address's host (nil after a disconnect)
        let server = connection.serverName ?? connection.serverURL?.host() ?? "Jellyfin"
        HStack(spacing: 0) {
            VStack(spacing: 28) {
                Image(systemName: "server.rack")
                    .font(.system(size: 130))
                    .foregroundStyle(Color.biingeText.opacity(0.85))
                    .frame(width: 300, height: 300)
                    .background(Color.biingeFill(0.07), in: RoundedRectangle(cornerRadius: 64))
                    .overlay(RoundedRectangle(cornerRadius: 64).strokeBorder(Color.biingeFill(0.08), lineWidth: 2))
                    .overlay(alignment: .bottomTrailing) {
                        // Connected while this Apple TV holds a Jellyfin session
                        Image(systemName: connection.isConnected ? "checkmark" : "minus")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.biingeBackground)
                            .frame(width: 56, height: 56)
                            .background(connection.isConnected ? Color.biingeWatched : Color.biingeTextTertiary, in: Circle())
                            .padding(10)
                            .background(Color.biingeBackground, in: Circle())
                            .offset(x: 20, y: 20)
                    }
                Text(server)
                    .font(.system(size: 64, weight: .bold))
                    .tracking(-1.92)
                Text(connection.isConnected ? "Connected" : "Not connected on this Apple TV")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.biingeText.opacity(0.7))
                Text(connection.isConnected
                    ? "Movies and TV Shows from \(server) play on this Apple TV."
                    : "Sign in with your Jellyfin account to browse and play \(server). My Lists and Search work without it.")
                    .font(.system(size: 24))
                    .lineSpacing(6)
                    .foregroundStyle(Color.biingeText.opacity(0.5))
                    .frame(maxWidth: 620)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 80)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    fact("Server", value: connection.serverURL?.host() ?? "Set by your Biinge server")
                    fact("Jellyfin account", value: connection.userName ?? "—")
                    fact("Biinge account", value: authManager.user?.email ?? "")
                }
                .padding(10)
                .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 28))
                VStack(spacing: 10) {
                    NavigationLink {
                        TVStatisticsView(apiClient: apiClient)
                    } label: {
                        Label("Statistics", systemImage: "chart.bar.fill")
                    }
                    .buttonStyle(SettingsButtonStyle())
                    if connection.isConnected {
                        // Reconnect ends only this device's session and opens the connect screen with the user filled in
                        Button { Task { await connection.reconnect() } } label: {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SettingsButtonStyle())
                        Button { confirming = .disconnect } label: {
                            Label("Disconnect…", systemImage: "link.badge.minus")
                        }
                        .buttonStyle(SettingsButtonStyle(isDestructive: true))
                    } else {
                        // after Not Now, Connect brings the connect screen back
                        Button { connection.skippedConnect = false } label: {
                            Label("Connect Jellyfin", systemImage: "link")
                        }
                        .buttonStyle(SettingsButtonStyle())
                    }
                    Button { confirming = .logOut } label: {
                        Label("Log Out of Biinge…", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(SettingsButtonStyle(isDestructive: true))
                }
                .padding(.top, 20)
                Text("Apple TV follows the system appearance. Subtitle Style lives in the player.")
                    .font(.system(size: 22))
                    .lineSpacing(6)
                    .foregroundStyle(Color.biingeText.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.top, 16)
            }
            .padding(.leading, 40)
            .padding(.trailing, 140)
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.biingeText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.biingeBackground)
        // the confirmation holds focus until it closes
        .disabled(confirming != nil)
        .overlay {
            if let confirming {
                confirmation(confirming, server: server)
            }
        }
    }

    private func fact(_ label: String, value: String) -> some View {
        HStack(spacing: 24) {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(Color.biingeText.opacity(0.55))
        }
        .font(.system(size: 28))
        .padding(.horizontal, 26)
        .frame(minHeight: 80)
    }

    /// The full-screen confirmation over the blurred screen, with focus starting on Cancel
    private func confirmation(_ confirmation: Confirmation, server: String) -> some View {
        let isDisconnect = confirmation == .disconnect
        return VStack(spacing: 26) {
            Text(isDisconnect ? "Disconnect Jellyfin?" : "Log out of Biinge?")
                .font(.system(size: 60, weight: .bold))
                .tracking(-1.8)
            Text(isDisconnect
                ? "This Apple TV stops playing from \(server). You stay logged in to Biinge, and your lists and watched history stay."
                : "This Apple TV signs out of Biinge and Jellyfin. You’ll need your Biinge email and password to log back in.")
                .font(.system(size: 30))
                .lineSpacing(7)
                .foregroundStyle(Color.biingeText.opacity(0.7))
                .frame(maxWidth: 1000)
            VStack(spacing: 16) {
                Button(isDisconnect ? "Disconnect" : "Log Out") {
                    confirming = nil
                    if isDisconnect {
                        Task { await connection.disconnect(apiClient: apiClient) }
                    } else {
                        // RootContainer ends the Jellyfin connection when the biinge session ends
                        authManager.logout()
                    }
                }
                .buttonStyle(SettingsButtonStyle(isDestructive: true, isCentered: true))
                .focused($confirmFocus, equals: .confirm)
                Button("Cancel") { confirming = nil }
                    .buttonStyle(SettingsButtonStyle(isCentered: true))
                    .focused($confirmFocus, equals: .cancel)
            }
            .frame(width: 640)
            .padding(.top, 24)
            .defaultFocus($confirmFocus, .cancel)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.biingeText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.biingeScrim.opacity(0.7))
                .ignoresSafeArea()
        }
        // focus stays in the confirmation, so a swipe up can't reach the tab bar behind it
        .focusSection()
        .onExitCommand { confirming = nil }
    }
}

/// Settings' full-width row button: translucent at rest, light and raised while focused, with red text at rest when destructive
private struct SettingsButtonStyle: ButtonStyle {
    var isDestructive = false
    /// Centers the label (the confirmation's buttons)
    var isCentered = false

    func makeBody(configuration: Configuration) -> some View {
        Row(label: configuration.label, isDestructive: isDestructive, isCentered: isCentered)
    }

    /// Reads focus from the environment, which a ButtonStyle itself can't see
    private struct Row: View {
        let label: ButtonStyleConfiguration.Label
        let isDestructive: Bool
        let isCentered: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(isFocused ? Color.biingeFocusText : isDestructive ? Color.biingeError : Color.biingeText)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: isCentered ? .center : .leading)
                .background(isFocused ? Color.biingeFocusFill : Color.biingeFill(0.08), in: RoundedRectangle(cornerRadius: 22))
                // Reduce Motion keeps the light fill as the focus mark and drops the lift
                .scaleEffect(isFocused && !reduceMotion ? 1.04 : 1)
                .shadow(color: Color.biingeShadow.opacity(isFocused ? 0.45 : 0), radius: 20, y: 18)
                .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
        }
    }
}
