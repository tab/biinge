import SwiftUI

struct LoginView: View {
    let authManager: AuthManager
    let apiClient: APIClient

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 8
            && !isSubmitting
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(rgb: 0x181818), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 8) {
                    Text("biinge")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(Color.biingePrimary)
                    Text("Track what you watch")
                        .font(.biingeBody)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(spacing: 14) {
                    inputField("Email", text: $email, field: .email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    inputField("Password", text: $password, field: .password, secure: true)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.biingeFootnote)
                            .foregroundStyle(Color(rgb: 0xFF6B6B))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }

                    Button("Log In") {
                        Task { await submit() }
                    }
                    .buttonStyle(PrimaryButtonStyle(isLoading: isSubmitting))
                    .disabled(!canSubmit)
                    .padding(.top, 4)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
    }

    private func inputField(_ placeholder: String, text: Binding<String>, field: Field, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField("", text: text, prompt: prompt(placeholder))
            } else {
                TextField("", text: text, prompt: prompt(placeholder))
            }
        }
        .focused($focusedField, equals: field)
        .font(.biingeBody)
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundColor(.white.opacity(0.5))
    }

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        isSubmitting = true
        withAnimation { errorMessage = nil }
        do {
            try await authManager.login(
                using: apiClient,
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch {
            let message = (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
            withAnimation { errorMessage = message }
        }
        isSubmitting = false
    }
}
