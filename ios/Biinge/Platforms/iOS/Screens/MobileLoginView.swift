import SwiftUI

struct MobileLoginView: View {
    @State private var flow: LoginFlow
    @FocusState private var focusedField: LoginField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(authManager: AuthManager, apiClient: APIClient) {
        _flow = State(initialValue: LoginFlow(authManager: authManager, apiClient: apiClient))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 15) {
                inputField("Email", text: $flow.email, field: .email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                inputField("Password", text: $flow.password, field: .password, secure: true)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { submit() }

                if let failure = flow.failure {
                    Text(failure.message)
                        .font(.biingeFootnote)
                        .foregroundStyle(Color.biingeError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.fieldMessage(reduceMotion: reduceMotion))
                }

                Button {
                    submit()
                } label: {
                    Text("Log in")
                        .font(.biingeCallout)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(rgb: 0x181818), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.pressable)
                // dimmed and locked with the fields while the login runs
                .opacity(flow.isSubmitting || flow.isDone ? 0.5 : 1)
                .disabled(flow.isSubmitting || flow.isDone)
                .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.isSubmitting || flow.isDone)

                Text("API: \(Config.baseURL.absoluteString)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.biingeGray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 60)
        // an edit to either field clears the error and its rings
        .onChange(of: flow.email) { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { flow.failure = nil } }
        .onChange(of: flow.password) { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { flow.failure = nil } }
        // a submit's new failure, or its clearing, moves the message and the rings as an edit does
        .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.failure)
        .sensoryFeedback(.error, trigger: flow.failures)
        // the form is the keyboard-avoiding layer; the artwork stays full-bleed behind it
        .background { BrandBackground() }
    }

    /// A form field, ringed red while a failed login names it and dimmed and locked while the login runs
    private func inputField(_ placeholder: String, text: Binding<String>, field: LoginField, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField("", text: text, prompt: prompt(placeholder))
            } else {
                TextField("", text: text, prompt: prompt(placeholder))
            }
        }
        .focused($focusedField, equals: field)
        .font(.system(.callout))
        .foregroundStyle(Color.biingeText)
        .padding(12)
        .background(Color.biingeCard, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.biingeError, lineWidth: 1.5)
                .opacity(flow.failure?.fields.contains(field) == true ? 1 : 0)
        )
        .opacity(flow.isSubmitting || flow.isDone ? 0.5 : 1)
        .disabled(flow.isSubmitting || flow.isDone)
        .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.isSubmitting || flow.isDone)
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Color.biingeGray)
    }

    /// Drops the keyboard and submits the form
    private func submit() {
        focusedField = nil
        Task { await flow.submit() }
    }
}
