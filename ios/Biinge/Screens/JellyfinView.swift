import SwiftUI
import UniformTypeIdentifiers

/// Profile → Jellyfin: issues or revokes the webhook token and walks through the Jellyfin side of the setup
struct JellyfinView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var token: String?
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var confirmRevoke = false

    var body: some View {
        ModalScaffold(title: "Jellyfin") {
            VStack(alignment: .leading, spacing: 28) {
                Text("Finish a movie or an episode in Jellyfin and it is marked watched here. "
                    + "Only titles already in your library are affected, and nothing is ever unmarked.")
                    .font(.biingeBody)
                    .foregroundStyle(.primary)

                tokenSection
                steps
            }
        }
        .confirmationDialog("Revoke the Jellyfin token?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Revoke", role: .destructive) { Task { await revoke() } }
        } message: {
            Text("Jellyfin stops syncing until you generate a new token and update the webhook header.")
        }
    }

    @ViewBuilder
    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Token")

            if let token {
                Text(token)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.biingeSecondaryCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("Copy it now. It is shown once and never again. The copy stays on this device and clears after two minutes.")
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)

                actionButton("Copy") {
                    // a credential should not follow Universal Clipboard to other devices or outlive the paste into Jellyfin
                    UIPasteboard.general.setItems(
                        [[UTType.utf8PlainText.identifier: token]],
                        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
                    )
                }
            } else {
                Text("This token is not your login. It only lets Jellyfin add watched marks to your library, "
                    + "so treat it like a password. Generating a new one replaces the old one.")
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.biingeFootnote)
                    .foregroundStyle(Color(rgb: 0xFF6B6B))
            }

            HStack(spacing: 12) {
                actionButton(token == nil ? "Generate token" : "Generate new token") {
                    Task { await generate() }
                }
                Button {
                    confirmRevoke = true
                } label: {
                    Text("Revoke")
                        .font(.biingeCaption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.pressable)
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Setup in Jellyfin")

            step(1, "Install the Webhook plugin from the Jellyfin catalog. You need admin rights on the server.")
            step(2, "Add a Generic Destination. Notification Type: User Data Saved. Item Type: Movies and Episodes. "
                + "Turn on Send All Properties.")
            step(3, "Set the User Filter to your own Jellyfin user. Every event with this token lands on your library, "
                + "whoever pressed play.")
            step(4, "Webhook Url:")

            // the API base already carries /api/v1
            Text(Config.baseURL.absoluteString + "/webhooks/jellyfin")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.biingeSecondaryCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            step(5, "Add a Request Header. Key: Authorization. Value: Bearer followed by a space and the token above. "
                + "Not the app's access or refresh token.")
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.biingeCaption2)
                .monospacedDigit()
                .foregroundStyle(Color.biingeBackground)
                .frame(width: 22, height: 22)
                .background(Color.biingeText, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(text)
                .font(.biingeFootnote)
                .foregroundStyle(.primary)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.biingeCaption2)
                .foregroundStyle(Color.biingeBackground)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.biingeText, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private func generate() async {
        guard let apiClient else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            token = try await apiClient.createJellyfinToken().token
        } catch {
            errorMessage = "Could not generate a token. Try again."
        }
    }

    private func revoke() async {
        guard let apiClient else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await apiClient.revokeJellyfin()
            token = nil
        } catch {
            errorMessage = "Could not revoke the token. Try again."
        }
    }
}
