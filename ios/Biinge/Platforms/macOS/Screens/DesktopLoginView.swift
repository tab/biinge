import SwiftUI

/// Mac biinge login: the setup card on the poster wall, at step 1 of the setup steps
struct DesktopLoginView: View {
    @State private var flow: LoginFlow
    /// Bumped by each failed login, which shakes the fields (not with Reduce Motion)
    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(authManager: AuthManager, apiClient: APIClient) {
        _flow = State(initialValue: LoginFlow(authManager: authManager, apiClient: apiClient))
    }

    var body: some View {
        VStack(spacing: 22) {
            SetupSteps(isConnectStep: false)
            VStack(spacing: 18) {
                Image("BrandIcon")
                    .resizable()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.biingeFill(0.12), lineWidth: 1))
                    .shadow(color: Color.biingeShadow.opacity(0.5), radius: 20, y: 16)
                Text("Biinge")
                    .font(.system(size: 56, weight: .bold))
                    .tracking(-1.96)
                    .padding(.top, 6)
                Text("Your personal media library.")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.biingeText.opacity(0.85))
            }

            VStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.biingeText.opacity(0.5))
                    TextField("", text: $flow.email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .macSetupField(isInvalid: flow.failure?.fields.contains(.email) == true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.biingeText.opacity(0.5))
                    SecureField("", text: $flow.password)
                        .textContentType(.password)
                        .macSetupField(isInvalid: flow.failure?.fields.contains(.password) == true)
                    if let failure = flow.failure {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                            Text(failure.message)
                        }
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color.biingeError)
                        .transition(.fieldMessage(reduceMotion: reduceMotion))
                    }
                }
            }
            .opacity(flow.isSubmitting || flow.isDone ? 0.5 : 1)
            .disabled(flow.isSubmitting || flow.isDone)
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.isSubmitting || flow.isDone)
            // the board's one shake, as macOS shakes a rejected password: −8, 7, −5 and 3 pt at 18, 38, 58 and 78 % of it
            .keyframeAnimator(initialValue: 0.0, trigger: shakes) { content, offset in
                content.offset(x: offset)
            } keyframes: { _ in
                LinearKeyframe(-8, duration: MotionDuration.shake * 0.18, timingCurve: MotionCurve.standard.unitCurve)
                LinearKeyframe(7, duration: MotionDuration.shake * 0.2, timingCurve: MotionCurve.standard.unitCurve)
                LinearKeyframe(-5, duration: MotionDuration.shake * 0.2, timingCurve: MotionCurve.standard.unitCurve)
                LinearKeyframe(3, duration: MotionDuration.shake * 0.2, timingCurve: MotionCurve.standard.unitCurve)
                LinearKeyframe(0, duration: MotionDuration.shake * 0.22, timingCurve: MotionCurve.standard.unitCurve)
            }
            // an edit to either field clears the error and its rings
            .onChange(of: flow.email) { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { flow.failure = nil } }
            .onChange(of: flow.password) { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { flow.failure = nil } }

            Button {
                Task { await flow.submit() }
            } label: {
                Text("Log in")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isFilled ? Color.biingeBackground : Color.biingeText.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isFilled ? Color.biingeText : Color.biingeFill(0.12), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            // dimmed and locked with the fields while the login runs
            .opacity(flow.isSubmitting || flow.isDone ? 0.5 : 1)
            .disabled(flow.isSubmitting || flow.isDone)
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.isSubmitting || flow.isDone)
        }
        // Return in either field submits
        .onSubmit { Task { await flow.submit() } }
        // a submit's new failure, or its clearing, moves the message and the rings as an edit does
        .animation(MotionCurve.standard.animation(MotionDuration.quick), value: flow.failure)
        .onChange(of: flow.failures) {
            if !reduceMotion { shakes += 1 }
        }
        .macSetupCard()
    }

    /// Both fields hold text, which lights the Log in button
    private var isFilled: Bool { !flow.email.isEmpty && !flow.password.isEmpty }
}

/// The setup card's two steps, "Biinge account" then "Jellyfin": the current one lit, a finished one checked in green
struct SetupSteps: View {
    /// Whether the Jellyfin step is the current one (the account step is done then)
    let isConnectStep: Bool

    var body: some View {
        HStack(spacing: 10) {
            step(number: 1, title: "Biinge account", isCurrent: !isConnectStep, isDone: isConnectStep)
            Rectangle()
                .fill(Color.biingeFill(0.2))
                .frame(width: 36, height: 1.5)
            step(number: 2, title: "Jellyfin", isCurrent: isConnectStep, isDone: false)
        }
        .font(.system(size: 13, weight: .semibold))
        .frame(maxWidth: .infinity)
    }

    private func step(number: Int, title: String, isCurrent: Bool, isDone: Bool) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().fill(isDone ? Color.biingeWatched : isCurrent ? Color.biingeText : Color.biingeFill(0.12))
                if isDone {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold))
                }
            }
            .frame(width: 22, height: 22)
            .foregroundStyle(isDone || isCurrent ? Color.biingeBackground : Color.biingeText.opacity(0.6))
            Text(title)
                .foregroundStyle(Color.biingeText.opacity(isDone || isCurrent ? 1 : 0.45))
        }
    }
}

extension View {
    /// Puts the view in the setup card on the poster wall that the Mac login and connect screens share, glass in the system appearance
    func macSetupCard(width: CGFloat = 520) -> some View {
        padding(.top, 40)
            .padding(.horizontal, 48)
            .padding(.bottom, 40)
            .frame(width: width)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    // the mockup's glass: rgba(28,28,34,.55) on dark, white 70% on light
                    Color.adaptive(light: 0xFFFFFF, dark: 0x1C1C22, lightOpacity: 0.7, darkOpacity: 0.55)
                }
                .clipShape(RoundedRectangle(cornerRadius: 30))
            }
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color.biingeFill(0.12), lineWidth: 1))
            .shadow(color: Color.biingeShadow.opacity(0.6), radius: 50, y: 40)
            .foregroundStyle(Color.biingeText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { SetupBackground() }
    }

    /// The Mac setup card's text field: plain text on a dimmed rounded box, ringed red when invalid
    func macSetupField(isInvalid: Bool = false) -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 17))
            .padding(.horizontal, 16)
            .frame(height: 50)
            // the mockup's black 35% box, which the light theme keeps at 30% of that
            .background(Color.adaptive(light: 0x000000, dark: 0x000000, lightOpacity: 0.105, darkOpacity: 0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isInvalid ? Color.biingeAccent : Color.biingeFill(0.14), lineWidth: isInvalid ? 1.5 : 1)
            )
    }
}
