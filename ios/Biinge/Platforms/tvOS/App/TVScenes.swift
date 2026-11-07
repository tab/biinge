import SwiftUI

extension BiingeApp {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            RootContainer(authManager: authManager, apiClient: apiClient, jellyfin: jellyfin)
                // Apple TV follows the system appearance
                .preferredColorScheme(nil)
        }
    }
}

extension RootContainer {
    /// The top tab shell once signed in
    var shell: some View {
        TVRootView(authManager: authManager, apiClient: apiClient, connection: jellyfin)
    }

    /// The login screen while signed out
    var login: some View {
        TVLoginView(authManager: authManager, apiClient: apiClient)
    }
}
