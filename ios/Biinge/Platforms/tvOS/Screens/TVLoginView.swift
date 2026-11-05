import SwiftUI

/// Apple TV biinge login on the setup poster wall: the icon and "Log in to Biinge", any error, then the fields
struct TVLoginView: View {
    @State private var flow: LoginFlow
    @FocusState private var focusedField: LoginField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(authManager: AuthManager, apiClient: APIClient) {
        _flow = State(initialValue: LoginFlow(authManager: authManager, apiClient: apiClient))
    }

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 22) {
                Image("BrandIcon")
                    .resizable()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                    .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color.biingeFill(0.12), lineWidth: 1))
                    .shadow(color: Color.biingeShadow.opacity(0.6), radius: 35, y: 30)
                Text("Log in to Biinge")
                    .font(.system(size: 80, weight: .bold))
                    .tracking(-2.8)
                Text("Use the Biinge account you have on iPhone. Your lists and watched history come with it.")
                    .font(.system(size: 30))
                    .lineSpacing(6)
                    .foregroundStyle(Color.biingeText.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1000)
            }

            // the mockup puts the error under the heading, above the fields
            if let failure = flow.failure {
                Label(failure.message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.biingeError)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1000)
                    .padding(.top, -14)
                    .transition(.fieldMessage(reduceMotion: reduceMotion))
            }

            VStack(spacing: 20) {
                TextField("", text: $flow.email, prompt: Text("Email"))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
                    .font(.system(size: 40))
                    // a focused field shows tvOS's own light platter, so the drawn box steps aside and the text turns dark
                    .foregroundStyle(focusedField == .email ? Color(rgb: 0x101014) : Color.biingeText)
                    .frame(width: 1000, height: 96)
                    .background(Color.biingeFill(focusedField == .email ? 0 : 0.1), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(flow.failure?.fields.contains(.email) == true ? Color.biingeError : Color.biingeFill(focusedField == .email ? 0 : 0.18), lineWidth: 2)
                    )
                SecureField("", text: $flow.password, prompt: Text("Password"))
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit { submit() }
                    .font(.system(size: 40))
                    .foregroundStyle(focusedField == .password ? Color(rgb: 0x101014) : Color.biingeText)
                    .frame(width: 1000, height: 96)
                    .background(Color.biingeFill(focusedField == .password ? 0 : 0.1), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(flow.failure?.fields.contains(.password) == true ? Color.biingeError : Color.biingeFill(focusedField == .password ? 0 : 0.18), lineWidth: 2)
                    )
            }
            .opacity(flow.isSubmitting || flow.isDone ? 0.5 : 1)
            .disabled(flow.isSubmitting || flow.isDone)
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.isSubmitting || flow.isDone)
            // an edit to either field clears the error and its rings
            .onChange(of: flow.email) { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { flow.failure = nil } }
            .onChange(of: flow.password) { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { flow.failure = nil } }

            // the button dims with the fields while it waits but stays enabled, as disabling it would drop the focus its pill reads from (the flow ignores a second press)
            Button("Log in") {
                submit()
            }
            .buttonStyle(TVSetupButtonStyle(isPrimary: true))
            // VoiceOver's busy cue, as the enabled button can't read as dimmed
            .accessibilityValue(flow.isSubmitting ? "In progress" : "")
            .opacity(flow.isSubmitting || flow.isDone ? 0.5 : 1)
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.isSubmitting || flow.isDone)
        }
        .foregroundStyle(Color.biingeText)
        // a submit's new failure, or its clearing, moves the message and the rings as an edit does
        .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.failure)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SetupBackground() }
    }

    /// Drops the keyboard and submits the form
    private func submit() {
        focusedField = nil
        Task { await flow.submit() }
    }
}
