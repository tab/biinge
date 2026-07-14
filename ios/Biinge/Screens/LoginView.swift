import SwiftUI
import UIKit

struct LoginView: View {
    let authManager: AuthManager
    let apiClient: APIClient

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var backgroundImage: UIImage?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 15) {
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
                }

                Button {
                    Task { await submit() }
                } label: {
                    ZStack {
                        Text("Login or Register")
                            .font(.biingeCallout)
                            .foregroundStyle(.white)
                            .opacity(isSubmitting ? 0 : 1)
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(rgb: 0x181818), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .opacity(isSubmitting ? 0.5 : 1)
                .disabled(isSubmitting)

                Text("API: \(Config.baseURL.absoluteString)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.biingeGray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 60)
        // the form is the keyboard-avoiding layer; the artwork ignores every safe area to stay full-bleed
        .background {
            ZStack {
                Color.black

                if let backgroundImage {
                    Image(uiImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                }

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.55), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .task {
            // pre-decode the full-screen PNG off the main thread to avoid a first-render hitch
            backgroundImage = await UIImage(named: "LoginBackground")?.byPreparingForDisplay()
        }
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
        .font(.system(size: 16))
        .foregroundStyle(Color.biingeText)
        .padding(12)
        .background(Color.biingeCard, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundColor(Color.biingeGray)
    }

    private func submit() async {
        focusedField = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty, password.count >= 8 else {
            withAnimation { errorMessage = "Enter a valid email and password (8+ characters)." }
            return
        }
        isSubmitting = true
        withAnimation { errorMessage = nil }
        do {
            try await authManager.login(using: apiClient, email: trimmedEmail, password: password)
        } catch {
            let message = (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
            withAnimation { errorMessage = message }
        }
        isSubmitting = false
    }
}
