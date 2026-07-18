import SwiftUI
import Observation

/// Owns the session: tokens, the current user, and the login/refresh/logout flow
@MainActor
@Observable
final class AuthManager {
    private(set) var user: User?
    private(set) var accessToken: String?
    private(set) var isRestoring = true

    private var refreshToken: String?
    private var refreshTask: Task<Void, Error>?
    private let keychain = Keychain()

    var isAuthenticated: Bool { user != nil }

    /// The preferred color scheme derived from the signed-in user's appearance
    var colorScheme: ColorScheme? {
        switch user?.appearance {
        case .dark: return .dark
        case .light: return .light
        default: return nil
        }
    }

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

    func login(using apiClient: APIClient, email: String, password: String) async throws {
        let tokens = try await apiClient.login(email: email, password: password)
        store(tokens)
        do {
            user = try await apiClient.me()
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
