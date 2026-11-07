import SwiftUI

extension BiingeApp {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            RootContainer(authManager: authManager, apiClient: apiClient, jellyfin: jellyfin)
                .preferredColorScheme(authManager.user?.appearance.colorScheme)
        }
    }
}

extension RootContainer {
    /// The tab shell once signed in
    var shell: some View {
        MobileRootView(authManager: authManager, apiClient: apiClient, connection: jellyfin)
    }

    /// The login screen while signed out
    var login: some View {
        MobileLoginView(authManager: authManager, apiClient: apiClient)
    }
}
