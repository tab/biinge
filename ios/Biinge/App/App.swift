import SwiftUI

/// The app's shared state (each platform's scenes come from its `*Scenes.swift`)
@main
struct BiingeApp: App {
    @State var authManager: AuthManager
    @State var apiClient: APIClient
    @State var jellyfin = JellyfinConnection(deviceID: { JellyfinConnection.storedDeviceID() })
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        Monitoring.start()
        let authManager = AuthManager()
        _authManager = State(initialValue: authManager)
        _apiClient = State(initialValue: APIClient(baseURL: Config.baseURL, authManager: authManager))
    }
}

/// Splash while restoring the session, then the login or authenticated shell (each platform's `*Scenes.swift` supplies `shell` and `login`)
struct RootContainer: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let jellyfin: JellyfinConnection

    var body: some View {
        Group {
            if authManager.isRestoring {
                SplashView()
            } else if authManager.isAuthenticated {
                shell
            } else {
                login
            }
        }
        .task {
            await authManager.restore(using: apiClient)
            #if DEBUG
            await debugAutoLoginIfNeeded()
            #endif
            // a session that ended while the app was closed leaves no Jellyfin session on this device behind
            // (only the device's: without a biinge token there's no API call, so the account stays connected)
            if !authManager.isAuthenticated {
                await jellyfin.disconnect()
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            // Log out ends only this device's Jellyfin session, as the biinge token is already gone
            if !isAuthenticated {
                Task { await jellyfin.disconnect() }
            }
        }
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
