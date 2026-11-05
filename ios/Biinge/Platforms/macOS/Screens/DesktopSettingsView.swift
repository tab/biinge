import SwiftUI

/// Mac Settings window: the biinge account with Log Out, the Jellyfin server's state with Connect, Reconnect and Disconnect, and the account's Appearance
struct DesktopSettingsView: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let connection: JellyfinConnection

    @State private var isConfirmingDisconnect = false
    @State private var isConfirmingLogOut = false
    /// The appearance whose write is in flight (the control shows it until the account answers)
    @State private var pickedAppearance: Appearance?
    @State private var appearanceError: String?

    var body: some View {
        // the server check's name, else the address's host (nil after a disconnect)
        let server = connection.serverName ?? connection.serverURL?.host() ?? "Jellyfin"
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Biinge account")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                HStack(spacing: 14) {
                    let name = authManager.user?.firstName ?? ""
                    Text(name.prefix(1).uppercased())
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.primary.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 15.5, weight: .semibold))
                        Text(authManager.user?.email ?? "")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Log Out…") { isConfirmingLogOut = true }
                        .disabled(!authManager.isAuthenticated)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Jellyfin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .bottomTrailing) {
                                // Connected while this Mac holds a Jellyfin session
                                Circle()
                                    .fill(connection.isConnected ? Color.biingeWatched : Color.biingeTextTertiary)
                                    .frame(width: 13, height: 13)
                                    .offset(x: 3, y: 3)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server)
                                .font(.system(size: 20, weight: .semibold))
                            Text(connection.isConnected ? "Connected" : "Not connected on this Mac")
                                .font(.system(size: 13.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if connection.isConnected {
                            // Reconnect ends only this device's session and keeps the user, so the main window's connect screen opens with it filled in
                            Button("Reconnect", systemImage: "arrow.clockwise") {
                                Task { await connection.reconnect() }
                            }
                        } else {
                            // after Not Now, Connect brings the main window's connect screen back
                            Button("Connect Jellyfin") { connection.skippedConnect = false }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    Divider()
                    LabeledContent("Server") {
                        Text(connection.serverURL?.host() ?? "—")
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 46)
                    .padding(.horizontal, 16)
                    Divider()
                    LabeledContent("Jellyfin account", value: connection.userName ?? "—")
                        .frame(minHeight: 46)
                        .padding(.horizontal, 16)
                }
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07)))
                HStack(spacing: 16) {
                    Text("Disconnecting keeps you logged in to Biinge. Lists, search and details keep working. Play needs Jellyfin.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if connection.isConnected {
                        Button("Disconnect…", role: .destructive) { isConfirmingDisconnect = true }
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                HStack(spacing: 20) {
                    Text("Theme")
                    Spacer()
                    Picker("Theme", selection: appearanceSelection) {
                        Text("System").tag(Appearance.system)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(authManager.user == nil)
                }
                .frame(minHeight: 54)
                .padding(.horizontal, 16)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07)))
                if let appearanceError {
                    Text(appearanceError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(32)
        .frame(width: 600)
        .confirmationDialog("Disconnect Jellyfin?", isPresented: $isConfirmingDisconnect) {
            Button("Disconnect", role: .destructive) {
                Task { await connection.disconnect(apiClient: apiClient) }
            }
        } message: {
            Text("This Mac stops playing from \(server). You stay logged in to Biinge, and your lists and watched history stay.")
        }
        .confirmationDialog("Log out of Biinge?", isPresented: $isConfirmingLogOut) {
            // RootContainer ends the Jellyfin connection when the biinge session ends
            Button("Log Out", role: .destructive) { authManager.logout() }
        } message: {
            Text("This Mac signs out of Biinge and Jellyfin. You’ll need your Biinge email and password to log back in.")
        }
    }

    /// The picked appearance while its write runs, then the account's (so a failed write reverts the control)
    private var appearanceSelection: Binding<Appearance> {
        Binding {
            pickedAppearance ?? authManager.user?.appearance ?? .system
        } set: { appearance in
            pickedAppearance = appearance
            appearanceError = nil
            Task {
                // updateAppearance updates the account's user only when the write succeeds
                await authManager.updateAppearance(appearance, using: apiClient)
                // a newer pick owns the control and its error
                guard pickedAppearance == appearance else { return }
                if authManager.user?.appearance != appearance {
                    appearanceError = "Couldn’t save the appearance. Try again."
                }
                pickedAppearance = nil
            }
        }
    }
}
