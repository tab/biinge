import SwiftUI

extension BiingeApp {
    @SceneBuilder var body: some Scene {
        // one main window, so File has no New Window and the menu actions always reach this shell
        Window("Biinge", id: "main") {
            RootContainer(authManager: authManager, apiClient: apiClient, jellyfin: jellyfin)
                // closing the main window quits the app, even with the Settings window open
                .onDisappear { NSApp.terminate(nil) }
        }
        // the setup card's poster wall runs up under the traffic lights
        .windowStyle(.hiddenTitleBar)
        // every launch fills the screen's visible area instead of restoring the last frame, without entering fullscreen
        .defaultWindowPlacement { _, context in
            WindowPlacement(.center, size: context.defaultDisplay.visibleRect.size)
        }
        .restorationBehavior(.disabled)
        .commands {
            SidebarCommands()
            BackCommands()
            SearchCommands()
        }
        // the app-wide appearance themes the main and Settings windows together, and nil really returns to System,
        // which .preferredColorScheme doesn't do reliably on macOS once it held an explicit scheme
        .onChange(of: authManager.user?.appearance.colorScheme, initial: true) { _, colorScheme in
            switch colorScheme {
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            default: NSApp.appearance = nil
            }
        }

        Settings {
            DesktopSettingsView(authManager: authManager, apiClient: apiClient, connection: jellyfin)
        }
    }
}

extension RootContainer {
    /// The sidebar shell once signed in
    var shell: some View {
        DesktopRootView(connection: jellyfin, apiClient: apiClient, authManager: authManager)
    }

    /// The login screen while signed out
    var login: some View {
        DesktopLoginView(authManager: authManager, apiClient: apiClient)
    }
}
