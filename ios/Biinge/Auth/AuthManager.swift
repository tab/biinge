import SwiftUI
import Observation

/// Owns the session: in-memory + Keychain tokens, the current user, and the
/// login/refresh/logout flow. The APIClient performs the token exchange over
/// the wire; this type owns storage and orchestration.
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

    /// The preferred color scheme derived from the signed-in user's appearance.
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

    /// Restores a session on launch by fetching the current user with the stored
    /// token (which the client will refresh if it has expired).
    func restore(using apiClient: APIClient) async {
        defer { isRestoring = false }
        guard accessToken != nil else { return }
        do {
            user = try await apiClient.me()
        } catch {
            clearSession()
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

    /// Persist a new appearance and update the in-memory user (which re-themes the app).
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

    /// Exchanges the refresh token for a new pair, or clears the session and
    /// surfaces `.unauthorized` if it can't. Concurrent callers (e.g. the several
    /// requests that 401 together on launch) coalesce onto a single in-flight
    /// refresh, so the refresh token is only spent once per cycle.
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
                clearSession()
                throw APIError.unauthorized
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
}
