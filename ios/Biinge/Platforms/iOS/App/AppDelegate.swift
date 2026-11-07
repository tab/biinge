import UIKit

/// Keeps the iPhone app in portrait, except while the player shows
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set while the player's window shows, so the player turns with the phone
    static var allowsLandscape = false

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowsLandscape ? .allButUpsideDown : .portrait
    }
}
