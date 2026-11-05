import Observation

/// Owns the session: tokens, the current user, and the login/refresh/logout flow
@MainActor
@Observable
final class AuthManager {
    private(set) var user: User?
    private(set) var accessToken: String?
    private(set) var isRestoring = true
    /// Set by a login in this launch (a restored session leaves it false), so the iPhone opens Connect Jellyfin before the tabs until the user connects or picks Not Now
    var connectsJellyfinFirst = false
    /// Counts the sessions ended in this launch, so a write deferred in one session can tell it has ended
    private(set) var sessionsEnded = 0

    private var refreshToken: String?
    private var refreshTask: Task<Void, Error>?
    private let keychain = Keychain()

    var isAuthenticated: Bool { user != nil }

    init() {
        accessToken = keychain.read(.accessToken)
        refreshToken = keychain.read(.refreshToken)
    }

    /// Restores a session on launch by fetching the current user with the stored token
    func restore(using apiClient: APIClient) async {
        defer { isRestoring = false }
        guard accessToken != nil else { return }
        do {
            user = try await apiClient.me()
        } catch {
            // Only drop the session when the token was actually rejected
            if Self.isSessionInvalid(error) {
                clearSession()
            }
        }
    }

    /// Signs in, running `beforeSignIn` once the API accepts the login and before the user swaps the root to the next screen
    func login(using apiClient: APIClient, email: String, password: String, beforeSignIn: () async -> Void = {}) async throws {
        let tokens = try await apiClient.login(email: email, password: password)
        store(tokens)
        do {
            let user = try await apiClient.me()
            await beforeSignIn()
            self.user = user
            connectsJellyfinFirst = true
        } catch {
            clearSession()
            throw error
        }
    }

    func logout() {
        clearSession()
    }

    /// Persist a new appearance and update the in-memory user (which re-themes the app)
    func updateAppearance(_ appearance: Appearance, using apiClient: APIClient) async {
        guard let user else { return }
        let body = UpdateAccountBody(
            firstName: user.firstName ?? "User",
            lastName: user.lastName ?? "User",
            appearance: appearance.rawValue
        )
        if let updated = try? await apiClient.updateAccount(body) {
            self.user = updated
        }
    }

    /// Exchanges the refresh token for a new pair, coalescing concurrent callers onto one refresh
    func refreshTokens(using apiClient: APIClient) async throws {
        if let inFlight = refreshTask {
            try await inFlight.value
            return
        }
        let task = Task { @MainActor [self] in
            defer { refreshTask = nil }
            guard let refreshToken else {
                clearSession()
                throw APIError.unauthorized
            }
            do {
                let tokens = try await apiClient.refresh(refreshToken: refreshToken)
                store(tokens)
            } catch {
                // A rejected token ends the session; a transient error keeps it
                if Self.isSessionInvalid(error) {
                    clearSession()
                    throw APIError.unauthorized
                }
                throw error
            }
        }
        refreshTask = task
        try await task.value
    }

    private func store(_ tokens: TokenPair) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        keychain.save(tokens.accessToken, for: .accessToken)
        keychain.save(tokens.refreshToken, for: .refreshToken)
    }

    private func clearSession() {
        sessionsEnded += 1
        user = nil
        accessToken = nil
        refreshToken = nil
        keychain.delete(.accessToken)
        keychain.delete(.refreshToken)
    }

    /// Whether the error means the stored session is genuinely invalid
    private static func isSessionInvalid(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        switch apiError {
        case .unauthorized, .badRequest:
            return true
        case .invalidResponse, .server, .network, .decoding:
            return false
        }
    }
}

/// A login form's field, which a failed login can ring
enum LoginField {
    case email, password
}

/// Why a login failed: the message under the fields and the fields at fault
struct LoginFailure: Equatable {
    let message: String
    let fields: Set<LoginField>
}

extension LoginFailure {
    /// The failure of a form that can't be sent, an empty email or a password under 8 characters (nil when it can be sent)
    init?(email: String, password: String) {
        var fields: Set<LoginField> = []
        if email.isEmpty { fields.insert(.email) }
        if password.count < 8 { fields.insert(.password) }
        guard !fields.isEmpty else { return nil }
        self.init(message: "Enter a valid email and password (8+ characters).", fields: fields)
    }

    /// The failure of a sent login (rejected credentials ring both fields, a validation message the field it names, anything else neither)
    init(_ error: any Error) {
        switch error as? APIError {
        case .unauthorized:
            // the API answers 401 for an unknown email and a wrong password alike, so neither field is singled out
            self.init(message: "That email and password don’t match a Biinge account.", fields: [.email, .password])
        case .badRequest(let message):
            self.init(message: message, fields: [message.localizedCaseInsensitiveContains("password") ? .password : .email])
        case let error?:
            self.init(message: error.errorDescription ?? "Something went wrong. Please try again.", fields: [])
        case nil:
            self.init(message: "Something went wrong. Please try again.", fields: [])
        }
    }
}
