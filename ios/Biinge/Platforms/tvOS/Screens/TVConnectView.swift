import SwiftUI

/// Apple TV Jellyfin connect flow on the setup poster wall: finding the server, sign-in, connecting with Cancel, and the server errors, each with Not Now
struct TVConnectView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient

    private enum Field {
        case user, password
    }

    @State private var flow: ConnectFlow
    @FocusState private var focusedField: Field?

    init(connection: JellyfinConnection, apiClient: APIClient) {
        self.connection = connection
        self.apiClient = apiClient
        _flow = State(initialValue: ConnectFlow(connection: connection, apiClient: apiClient))
    }

    var body: some View {
        VStack(spacing: 40) {
            // a failed Disconnect left the account connected in the API, which a retry clears without signing in again
            if connection.accountDisconnectFailed {
                HStack(spacing: 24) {
                    Text("Couldn’t disconnect your biinge account from Jellyfin.")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.biingeError)
                    Button("Try Again") { Task { await connection.retryAccountDisconnect(apiClient: apiClient) } }
                        .buttonStyle(TVSetupButtonStyle())
                }
            }
            switch flow.step {
            case .checking: connecting(title: "Connecting to Jellyfin", detail: nil)
            case .signIn: signIn
            case .connecting:
                connecting(title: "Connecting to \(flow.serverName)", detail: "Signing in as \(flow.user)")
                Button("Cancel") { flow.cancel() }
                    .buttonStyle(TVSetupButtonStyle())
            case .unreachable(let message): unreachable(message)
            case .noServer: noServer
            }
        }
        .foregroundStyle(Color.biingeText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SetupBackground() }
        // Try Again goes back to Checking, which runs the check again
        .task(id: flow.step) {
            if flow.step == .checking { await flow.check() }
        }
    }

    @ViewBuilder private var signIn: some View {
        VStack(spacing: 20) {
            Text("Connect Jellyfin")
                .font(.system(size: 72, weight: .bold))
                .tracking(-2.16)
            Text("Sign in with your Jellyfin account once. It links \(flow.serverName) to your Biinge account and this Apple TV.")
                .font(.system(size: 30))
                .lineSpacing(7)
                .foregroundStyle(Color.biingeText.opacity(0.65))
                .frame(maxWidth: 1000)
        }
        // the mockup puts the error under the heading, above the fields
        if let errorMessage = flow.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.biingeError)
                .frame(maxWidth: 1000)
                .padding(.top, -14)
        }
        VStack(spacing: 20) {
            HStack(spacing: 24) {
                Image(systemName: "server.rack")
                    .font(.system(size: 32))
                    .frame(width: 72, height: 72)
                    .background(Color.biingeFill(0.1), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(flow.serverName)
                        .font(.system(size: 32, weight: .semibold))
                    Text(URL(string: flow.server)?.host() ?? flow.server)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.biingeText.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 24)
            .frame(width: 1000, height: 112)
            .background(Color.biingeFill(0.06), in: RoundedRectangle(cornerRadius: 24))
            TextField("", text: $flow.user, prompt: Text("User"))
                .focused($focusedField, equals: .user)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .tvSetupField(text: flow.user, prompt: "User", isFocused: focusedField == .user)
            SecureField("", text: $flow.password, prompt: Text("Password"))
                .focused($focusedField, equals: .password)
                .textContentType(.password)
                .onSubmit { Task { await flow.connect() } }
                .tvSetupField(text: flow.password, prompt: "Password", isSecure: true, isFocused: focusedField == .password)
        }
        HStack(spacing: 20) {
            Button("Connect") { Task { await flow.connect() } }
                .buttonStyle(TVSetupButtonStyle(isPrimary: true))
            Button("Not Now") { connection.skippedConnect = true }
                .buttonStyle(TVSetupButtonStyle())
        }
    }

    @ViewBuilder private func connecting(title: String, detail: String?) -> some View {
        VStack(spacing: 28) {
            // the mockup's ring: a dim track with one bright quarter turning every 0.9 s
            TimelineView(.animation) { context in
                ZStack {
                    Circle().stroke(Color.biingeFill(0.15), lineWidth: 6)
                    Circle().trim(from: 0, to: 0.25).stroke(Color.biingeText, lineWidth: 6)
                }
                .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
            }
            .frame(width: 78, height: 78)
            .padding(3)
            Text(title)
                .font(.system(size: 60, weight: .bold))
                .tracking(-1.8)
            if let detail {
                Text(detail)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.biingeText.opacity(0.55))
            }
        }
    }

    @ViewBuilder private func unreachable(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.biingeError)
                .frame(width: 110, height: 110)
                .background(Color.biingeError.opacity(0.16), in: Circle())
            Text("Can’t reach \(flow.serverName)")
                .font(.system(size: 64, weight: .bold))
                .tracking(-1.92)
            Text("Biinge couldn’t get through to \(URL(string: flow.server)?.host() ?? "the server"). The server may be off, or out of reach from this network.")
                .font(.system(size: 30))
                .lineSpacing(7)
                .foregroundStyle(Color.biingeText.opacity(0.7))
                .frame(maxWidth: 1000)
            Text(message)
                .font(.system(size: 24, design: .monospaced))
                .foregroundStyle(Color.biingeText.opacity(0.5))
        }
        HStack(spacing: 20) {
            Button("Try Again") { flow.step = .checking }
            Button("Not Now") { connection.skippedConnect = true }
        }
        .buttonStyle(TVSetupButtonStyle())
    }

    @ViewBuilder private var noServer: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 48, weight: .medium))
                .frame(width: 110, height: 110)
                .background(Color.biingeFill(0.1), in: Circle())
            Text("No Jellyfin server")
                .font(.system(size: 72, weight: .bold))
                .tracking(-2.16)
            Text(JellyfinConnectionError.noServer.localizedDescription)
                .font(.system(size: 30))
                .lineSpacing(7)
                .foregroundStyle(Color.biingeText.opacity(0.7))
                .frame(maxWidth: 1000)
        }
        Button("Not Now") { connection.skippedConnect = true }
            .buttonStyle(TVSetupButtonStyle(isPrimary: true))
    }
}
