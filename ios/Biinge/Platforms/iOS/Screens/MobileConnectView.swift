import SwiftUI

/// iPhone Jellyfin connect flow, after a fresh login and in Profile's Jellyfin sheet: finding the server, sign-in, connecting with Cancel, and the server errors
struct MobileConnectView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// Leaves the flow without Jellyfin (nil in the sheet, which closes with its own button)
    let notNow: (() -> Void)?

    private enum Field {
        case user, password
    }

    @State private var flow: ConnectFlow
    @FocusState private var focusedField: Field?

    init(connection: JellyfinConnection, apiClient: APIClient, notNow: (() -> Void)? = nil) {
        self.connection = connection
        self.apiClient = apiClient
        self.notNow = notNow
        _flow = State(initialValue: ConnectFlow(connection: connection, apiClient: apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // a failed Disconnect left the account connected in the API, which a retry clears without signing in again
            if connection.accountDisconnectFailed {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Couldn’t disconnect your Biinge account from Jellyfin.")
                    Spacer(minLength: 0)
                    Button {
                        Task { await connection.retryAccountDisconnect(apiClient: apiClient) }
                    } label: {
                        Text("Try Again")
                            .fontWeight(.semibold)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
                .font(.subheadline)
                .foregroundStyle(Color.biingeError)
            }
            switch flow.step {
            case .checking:
                connecting(title: "Connecting to Jellyfin", detail: nil)
            case .signIn:
                signIn
            case .connecting:
                connecting(title: "Connecting to \(flow.serverName)", detail: "Signing in as \(flow.user)")
                capsule("Cancel", isPrimary: false) { flow.cancel() }
            case .unreachable(let message):
                unreachable(message)
            case .noServer:
                noServer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Try Again goes back to Checking, which runs the check again
        .task(id: flow.step) {
            if flow.step == .checking { await flow.check() }
        }
        // closing the sheet mid sign-in drops it, as Cancel does
        .onDisappear {
            if flow.step == .connecting { connection.cancelConnect() }
        }
    }

    @ViewBuilder private var signIn: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.body)
                .frame(width: 38, height: 38)
                .background(Color.biingeFill(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(flow.serverName)
                    .font(.body.weight(.semibold))
                Text(URL(string: flow.server)?.host() ?? flow.server)
                    .font(.footnote)
                    .foregroundStyle(Color.biingeTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.biingeFill(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.biingeFill(0.08)))

        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Username")
                        .foregroundStyle(Color.biingeTextSecondary)
                    TextField("Username", text: $flow.user, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .user)
                        .onSubmit { focusedField = .password }
                }
                .frame(minHeight: 52)
                .padding(.horizontal, 16)
                Divider().overlay(Color.biingeFill(0.07))
                HStack(spacing: 12) {
                    Text("Password")
                        .foregroundStyle(Color.biingeTextSecondary)
                    SecureField("Password", text: $flow.password, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit { connect() }
                }
                .frame(minHeight: 52)
                .padding(.horizontal, 16)
            }
            .font(.body)
            .background(Color.biingeFill(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(flow.errorMessage == nil ? Color.biingeFill(0.08) : Color.biingeError))
            if let errorMessage = flow.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(errorMessage)
                }
                .font(.subheadline)
                .foregroundStyle(Color.biingeError)
                .padding(.horizontal, 4)
            }
            Text("One sign-in links \(flow.serverName) to your Biinge account and this iPhone.")
                .font(.subheadline)
                .foregroundStyle(Color.biingeTextSecondary)
                .padding(.horizontal, 4)
        }
        // an edit to either field clears the old error and its ring
        .onChange(of: flow.user) { flow.errorMessage = nil }
        .onChange(of: flow.password) { flow.errorMessage = nil }

        capsule("Connect") { connect() }
        if let notNow {
            Button(action: notNow) {
                Text("Not Now")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.biingeTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
    }

    private func connecting(title: String, detail: String?) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.biingeLoader)
            Text(title)
                .font(.biingeSubhead)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.biingeTextSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func unreachable(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash")
                .font(.title2.weight(.medium))
                .foregroundStyle(Color.biingeError)
                .frame(width: 64, height: 64)
                .background(Color.biingeError.opacity(0.15), in: Circle())
            Text("Can’t reach \(flow.serverName)")
                .font(.biingeSubhead)
            Text("Biinge couldn’t get through to \(URL(string: flow.server)?.host() ?? "the server"). The server may be off, or out of reach from this network.")
                .font(.subheadline)
                .foregroundStyle(Color.biingeTextSecondary)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(Color.biingeTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.biingeFill(0.06), in: RoundedRectangle(cornerRadius: 8))
            VStack(spacing: 10) {
                capsule("Try Again") { flow.step = .checking }
                if let notNow {
                    capsule("Not Now", isPrimary: false, action: notNow)
                }
            }
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var noServer: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.title2.weight(.medium))
                .frame(width: 64, height: 64)
                .background(Color.biingeFill(0.1), in: Circle())
            Text("No Jellyfin server")
                .font(.biingeSubhead)
            Text(JellyfinConnectionError.noServer.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(Color.biingeTextSecondary)
            if let notNow {
                capsule("Not Now", action: notNow)
                    .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// A full-width capsule button: the text color with the background's text when primary, the 12% fill otherwise
    private func capsule(_ title: String, isPrimary: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.biingeBackground : Color.biingeText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(isPrimary ? Color.biingeText : Color.biingeFill(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    /// Drops the keyboard and signs in
    private func connect() {
        focusedField = nil
        Task { await flow.connect() }
    }
}
