import SwiftUI

@main
struct BiingeApp: App {
    @State private var authManager: AuthManager
    @State private var apiClient: APIClient

    init() {
        let authManager = AuthManager()
        _authManager = State(initialValue: authManager)
        _apiClient = State(initialValue: APIClient(baseURL: Config.baseURL, authManager: authManager))
    }

    var body: some Scene {
        WindowGroup {
            RootContainer(authManager: authManager, apiClient: apiClient)
        }
    }
}

/// Splash while restoring the session, then the login or authenticated shell
struct RootContainer: View {
    let authManager: AuthManager
    let apiClient: APIClient

    var body: some View {
        Group {
            if authManager.isRestoring {
                SplashView()
            } else if authManager.isAuthenticated {
                RootView(authManager: authManager, apiClient: apiClient)
            } else {
                LoginView(authManager: authManager, apiClient: apiClient)
            }
        }
        .task {
            await authManager.restore(using: apiClient)
            #if DEBUG
            await debugAutoLoginIfNeeded()
            #endif
        }
        .preferredColorScheme(authManager.colorScheme)
    }

    #if DEBUG
    /// Signs in automatically when launched with AUTOLOGIN_EMAIL / AUTOLOGIN_PASSWORD
    private func debugAutoLoginIfNeeded() async {
        let env = ProcessInfo.processInfo.environment
        guard !authManager.isAuthenticated,
              let email = env["AUTOLOGIN_EMAIL"],
              let password = env["AUTOLOGIN_PASSWORD"] else {
            return
        }
        try? await authManager.login(using: apiClient, email: email, password: password)
    }
    #endif
}
