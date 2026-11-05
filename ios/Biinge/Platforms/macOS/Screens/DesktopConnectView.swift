import SwiftUI

/// Mac Jellyfin connect flow in the setup card on the poster wall, at step 2 of the setup steps: finding the server, sign-in, connecting with Cancel, and the server errors, each with Not Now
struct DesktopConnectView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    let authManager: AuthManager

    @State private var flow: ConnectFlow

    init(connection: JellyfinConnection, apiClient: APIClient, authManager: AuthManager) {
        self.connection = connection
        self.apiClient = apiClient
        self.authManager = authManager
        _flow = State(initialValue: ConnectFlow(connection: connection, apiClient: apiClient))
    }

    var body: some View {
        VStack(spacing: 20) {
            SetupSteps(isConnectStep: true)
                .padding(.bottom, 4)
            // a failed Disconnect left the account connected in the API, which a retry clears without signing in again
            if connection.accountDisconnectFailed {
                HStack(spacing: 12) {
                    Text("Couldn’t disconnect your biinge account from Jellyfin.")
                    Button("Try Again") { Task { await connection.retryAccountDisconnect(apiClient: apiClient) } }
                        .buttonStyle(.pressable)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14.5))
                .foregroundStyle(Color.biingeError)
            }
            switch flow.step {
            case .checking: connecting(title: "Connecting to Jellyfin", detail: nil)
            case .signIn: signIn
            case .connecting:
                connecting(title: "Connecting to \(flow.serverName)", detail: "Signing in as \(flow.user)")
                Button {
                    flow.cancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 24)
                        .frame(height: 44)
                        .background(Color.biingeFill(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            case .unreachable(let message): unreachable(message)
            case .noServer: noServer
            }
            // the biinge account stays visible, so the wrong one can be swapped before connecting
            if flow.step == .signIn || authManager.user?.email != nil {
                HStack(spacing: 6) {
                    if let email = authManager.user?.email {
                        Text("Logged in as \(email)")
                            .foregroundStyle(Color.biingeTextSecondary)
                        Text("·").foregroundStyle(Color.biingeTextTertiary)
                        Button("Log Out") { authManager.logout() }
                            .buttonStyle(.pressable)
                            .fontWeight(.semibold)
                    }
                    // the way out of sign-in, with or without an account to show
                    if flow.step == .signIn {
                        Spacer()
                        Button("Not Now") { connection.skippedConnect = true }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.biingeText.opacity(0.85))
                            .buttonStyle(.pressable)
                            .fixedSize()
                    }
                }
                .font(.system(size: 13))
                .lineLimit(flow.step == .signIn ? 1 : nil)
                .padding(.top, 4)
            }
        }
        .macSetupCard(width: 560)
        // Try Again goes back to Checking, which runs the check again
        .task(id: flow.step) {
            if flow.step == .checking { await flow.check() }
        }
    }

    @ViewBuilder private var signIn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect Jellyfin")
                .font(.system(size: 36, weight: .bold))
                .tracking(-1.08)
            Text("Sign in with your Jellyfin account once. It links \(flow.serverName) to your Biinge account and this Mac, so you won’t sign in to Jellyfin anywhere else in the app.")
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(Color.biingeText.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 18))
                .frame(width: 40, height: 40)
                .background(Color.biingeFill(0.1), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(flow.serverName)
                    .font(.system(size: 16, weight: .semibold))
                Text(URL(string: flow.server)?.host() ?? flow.server)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.biingeText.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.biingeFill(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.biingeFill(0.08)))
        VStack(alignment: .leading, spacing: 8) {
            Text("User")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.biingeText.opacity(0.5))
            TextField("", text: $flow.user)
                .textContentType(.username)
                .autocorrectionDisabled()
                .macSetupField(isInvalid: flow.errorMessage != nil)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Password")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.biingeText.opacity(0.5))
            SecureField("", text: $flow.password)
                .textContentType(.password)
                .onSubmit { Task { await flow.connect() } }
                .macSetupField(isInvalid: flow.errorMessage != nil)
            if let errorMessage = flow.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(errorMessage)
                }
                .font(.system(size: 14.5))
                .foregroundStyle(Color.biingeError)
            }
        }
        // an edit to either field clears the old error and its rings
        .onChange(of: flow.user) { flow.errorMessage = nil }
        .onChange(of: flow.password) { flow.errorMessage = nil }
        Button("Connect") { Task { await flow.connect() } }
            .buttonStyle(SetupButtonStyle())
    }

    private func connecting(title: String, detail: String?) -> some View {
        VStack(spacing: 18) {
            // the mockup's ring: a dim track with one bright quarter turning every 0.9 s
            TimelineView(.animation) { context in
                ZStack {
                    Circle().stroke(Color.biingeFill(0.15), lineWidth: 4)
                    Circle().trim(from: 0, to: 0.25).stroke(Color.biingeText, lineWidth: 4)
                }
                .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
            }
            .frame(width: 48, height: 48)
            .padding(2)
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.9)
                .padding(.top, 6)
            if let detail {
                Text(detail)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Color.biingeText.opacity(0.6))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, 30)
        .padding(.bottom, 10)
    }

    private func unreachable(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.biingeError)
                .frame(width: 64, height: 64)
                .background(Color.biingeError.opacity(0.15), in: Circle())
            Text("Can’t reach \(flow.serverName)")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.96)
            Text("Biinge couldn’t get through to \(URL(string: flow.server)?.host() ?? "the server"). The server may be off, or out of reach from this network.")
                .font(.system(size: 16.5))
                .lineSpacing(4)
                .foregroundStyle(Color.biingeText.opacity(0.7))
                .frame(maxWidth: 420)
            Text(message)
                .font(.system(size: 13.5, design: .monospaced))
                .foregroundStyle(Color.biingeText.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.biingeFill(0.06), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 12) {
                Button("Try Again") { flow.step = .checking }
                    .buttonStyle(SetupButtonStyle())
                Button("Not Now") { connection.skippedConnect = true }
                    .buttonStyle(SetupButtonStyle(isPrimary: false))
            }
            .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
    }

    private var noServer: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 26, weight: .medium))
                .frame(width: 64, height: 64)
                .background(Color.biingeFill(0.1), in: Circle())
            Text("No Jellyfin server")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.96)
            Text(JellyfinConnectionError.noServer.localizedDescription)
                .font(.system(size: 16.5))
                .lineSpacing(4)
                .foregroundStyle(Color.biingeText.opacity(0.7))
                .frame(maxWidth: 420)
            Button("Not Now") { connection.skippedConnect = true }
                .buttonStyle(SetupButtonStyle())
                .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
    }
}

/// The setup card's capsule button: the text color with the background's text when primary, the 12% fill otherwise, dimmed while disabled
private struct SetupButtonStyle: ButtonStyle {
    var isPrimary = true

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, isPrimary: isPrimary)
    }

    /// Reads the enabled state and Reduce Motion from the environment, which a ButtonStyle itself can't see
    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        let isPrimary: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let isLit = isPrimary && isEnabled
            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isLit ? Color.biingeBackground : Color.biingeText.opacity(isEnabled ? 1 : 0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isLit ? Color.biingeText : Color.biingeFill(0.12), in: Capsule())
                .contentShape(Capsule())
                // the same press feedback as PressableStyle, which the login button uses
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .animation(MotionCurve.standard.animation(MotionDuration.press), value: configuration.isPressed)
        }
    }
}
