import SwiftUI

extension BiingeApp {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            RootContainer(authManager: authManager, apiClient: apiClient, jellyfin: jellyfin)
        }
    }
}

extension RootContainer {
    /// The shell once signed in
    var shell: some View { EmptyView() }

    /// The login screen while signed out
    var login: some View { EmptyView() }
}
