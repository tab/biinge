/// The platform this app runs on, named for the User-Agent and for Jellyfin
enum DeviceInfo {
    #if os(macOS)
    /// The OS name the User-Agent carries
    static let osName = "macOS"
    /// The device name Jellyfin lists the session under
    static let deviceName = "Mac"
    #elseif os(tvOS)
    /// The OS name the User-Agent carries
    static let osName = "tvOS"
    /// The device name Jellyfin lists the session under
    static let deviceName = "Apple TV"
    #else
    /// The OS name the User-Agent carries
    static let osName = "iOS"
    /// The device name Jellyfin lists the session under
    static let deviceName = "iPhone"
    #endif
}
