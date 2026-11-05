import Foundation
import Observation

/// The biinge login form on every platform: the fields, the submit in flight, its success and the failure that rings the fields at fault
@MainActor
@Observable
final class LoginFlow {
    private let authManager: AuthManager
    private let apiClient: APIClient

    var email = ""
    var password = ""
    private(set) var isSubmitting = false
    /// Set once the login succeeds, which keeps the form locked until the root swaps to the next screen
    private(set) var isDone = false
    /// The last failed submit's message and fields (an edit to either field clears it)
    var failure: LoginFailure?
    /// Bumped by each failed submit, which plays a platform's feedback (iPhone's error haptic, the Mac's shake)
    private(set) var failures = 0

    init(authManager: AuthManager, apiClient: APIClient) {
        self.authManager = authManager
        self.apiClient = apiClient
    }

    /// Logs in with the trimmed email, or fails the form at once when it can't be sent (a second submit while one runs or after success does nothing)
    func submit() async {
        guard !isSubmitting, !isDone else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if let invalid = LoginFailure(email: trimmedEmail, password: password) {
            failure = invalid
            failures += 1
            return
        }
        isSubmitting = true
        failure = nil
        do {
            try await authManager.login(using: apiClient, email: trimmedEmail, password: password) {
                isSubmitting = false
                isDone = true
            }
        } catch {
            // the button lights again at once, ready for a retry
            isSubmitting = false
            failure = LoginFailure(error)
            failures += 1
        }
    }
}
