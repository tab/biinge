import Foundation
import Get
import JellyfinAPI
import Observation

enum JellyfinConnectionError: LocalizedError {
    case noServer
    case notHTTPS
    case notJellyfin
    case signInRejected
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noServer: "This Biinge server has no Jellyfin server set up."
        case .notHTTPS: "Biinge connects to a Jellyfin server only over https."
        case .notJellyfin: "No Jellyfin server answered at this address."
        case .signInRejected: "Jellyfin rejected this user or password."
        case .invalidResponse: "The server did not return a Jellyfin session."
        }
    }
}

/// Owns the one Jellyfin connection on this device: sign-in, restore on launch, Not Now and Disconnect
@MainActor
@Observable
final class JellyfinConnection {
    private(set) var client: JellyfinClient?
    private(set) var userID: String?
    /// The signed-in Jellyfin user's name, shown in Settings
    private(set) var userName: String?
    /// The Jellyfin server's name for the "Not on" note (kept from the server check across Not Now, nil after a disconnect)
    private(set) var serverName: String?
    /// The Jellyfin address the API reported in the last server check (kept when Jellyfin doesn't answer there, so the error can name it)
    private(set) var checkedAddress: String?
    /// The item playing now, owned here so Disconnect and Log out stop it
    private(set) var playback: PlaybackSession?
    /// Counts the playbacks whose stop report has gone out, so screens reload after it
    private(set) var playbackEnded = 0
    /// The last stopped play's fresh item when Jellyfin reports it played, nil otherwise (set before playbackEnded counts the play)
    private(set) var finishedPlay: BaseItemDto?
    /// The Jellyfin IDs of the items biinge marked watched on this device, which Home hides while Jellyfin may still report them unplayed (every disconnect clears them)
    private(set) var watchedIDs: Set<String> = []
    /// The user name Reconnect keeps for the connect screen (nil after a plain disconnect)
    private(set) var reconnectPrefill: String?
    /// Set when Disconnect's API call failed, so the account may still be connected in the API (a retry, a new connect and Log out clear it)
    private(set) var accountDisconnectFailed = false
    /// Set by Not Now, so the shell opens without Jellyfin (memory only, and every disconnect clears it, Log out's too)
    var skippedConnect = false
    /// Set when a Jellyfin call fails to reach the server and cleared by the next call it answers (every disconnect clears it)
    private(set) var isUnreachable = false
    /// Each list's last loaded first page, which a return to its grid shows at once (memory only, and every disconnect clears them)
    @ObservationIgnored var firstPages: [LibraryList: LibraryPage] = [:]
    /// Each library's last loaded genre names, which a return to its grid shows at once (memory only, and every disconnect clears them)
    @ObservationIgnored var genres: [BaseItemKind: [String]] = [:]

    private let keychain = Keychain()
    private let sessionConfiguration: URLSessionConfiguration
    private let deviceID: () -> String
    /// Bumped by every disconnect and by cancelConnect, so a sign-in that was in flight during one is dropped and an older service's calls report nothing
    private(set) var generation = 0

    var isConnected: Bool { client != nil }

    /// The connected server's address, nil while disconnected
    var serverURL: URL? { client?.configuration.url }

    /// The service for the connected user, nil while disconnected
    var service: (any JellyfinService)? {
        guard let client, let userID else { return nil }
        return JellyfinAPIService(client: client, userID: userID, connection: self, generation: generation)
    }

    /// Restores the stored connection (tests pass a configuration with a stub URL protocol and a fixed device ID, so they never reach the Keychain item)
    init(sessionConfiguration: URLSessionConfiguration = .default, deviceID: @escaping () -> String) {
        self.sessionConfiguration = sessionConfiguration
        self.deviceID = deviceID
        guard let server = keychain.read(.jellyfinServer).flatMap(URL.init(string:)),
              let token = keychain.read(.jellyfinToken),
              let userID = keychain.read(.jellyfinUserID) else {
            return
        }
        client = JellyfinClient(configuration: Self.configuration(url: server, accessToken: token, deviceID: deviceID()), sessionConfiguration: sessionConfiguration)
        self.userID = userID
        userName = keychain.read(.jellyfinUserName)
        serverName = keychain.read(.jellyfinServerName)
    }

    /// Reads the Jellyfin address from the API and checks that a Jellyfin server answers there over https (returns the address and the server's name, the host when it has none, and keeps the name)
    func checkServer(apiClient: APIClient) async throws -> (address: String, name: String) {
        // an earlier check's address would name the wrong server if the API itself can't answer
        checkedAddress = nil
        let address: String
        do {
            address = try await apiClient.jellyfinConnection().baseURL
        } catch APIError.server(status: 404) {
            // the API answers 404 when this instance has no Jellyfin server configured
            throw JellyfinConnectionError.noServer
        }
        checkedAddress = address
        guard let url = URL(string: address), url.scheme?.lowercased() == "https", let host = url.host() else {
            throw JellyfinConnectionError.notHTTPS
        }
        let client = JellyfinClient(configuration: Self.configuration(url: url, accessToken: nil, deviceID: deviceID()), sessionConfiguration: sessionConfiguration)
        do {
            let name = try await client.send(Paths.getPublicSystemInfo).value.serverName ?? host
            serverName = name
            return (address, name)
        } catch let error as URLError {
            throw error
        } catch {
            throw JellyfinConnectionError.notJellyfin
        }
    }

    /// Signs in to the server on this device, then connects the account in the API with the same credentials, and keeps the address, user ID, user name and access token, never the password
    func connect(server: String, user: String, password: String, apiClient: APIClient) async throws {
        guard let url = URL(string: server), url.scheme?.lowercased() == "https", url.host() != nil else {
            throw JellyfinConnectionError.notHTTPS
        }
        let client = JellyfinClient(configuration: Self.configuration(url: url, accessToken: nil, deviceID: deviceID()), sessionConfiguration: sessionConfiguration)
        let started = generation
        // a Jellyfin server answers its public info without sign-in, which tells a wrong address from a wrong password
        do {
            _ = try await client.send(Paths.getPublicSystemInfo)
        } catch let error as URLError {
            throw error
        } catch {
            throw JellyfinConnectionError.notJellyfin
        }
        // a Log out or Cancel during the server check stops before a session exists
        guard started == generation else { return }
        let result: AuthenticationResult
        do {
            result = try await client.signIn(username: user, password: password)
        } catch let error as URLError {
            throw error
        } catch {
            throw JellyfinConnectionError.signInRejected
        }
        // a Log out or Cancel during sign-in wins, so the new session never outlives the biinge one and the API never hears of it
        guard started == generation else {
            _ = try? await client.send(Paths.reportSessionEnded)
            return
        }
        guard let token = result.accessToken, let userID = result.user?.id else {
            throw JellyfinConnectionError.invalidResponse
        }
        do {
            _ = try await apiClient.connectJellyfin(JellyfinConnectionRequest(username: user, password: password))
        } catch {
            // the account didn't connect, so this device's new session ends too and nothing is kept
            _ = try? await client.send(Paths.reportSessionEnded)
            throw error
        }
        // a Log out or Cancel during the API connect wins as well
        guard started == generation else {
            // the account stays connected in the API, as other devices' Jellyfin writes rely on it (the state Reconnect leaves)
            _ = try? await client.send(Paths.reportSessionEnded)
            return
        }
        keychain.save(url.absoluteString, for: .jellyfinServer)
        keychain.save(userID, for: .jellyfinUserID)
        keychain.save(token, for: .jellyfinToken)
        let userName = result.user?.name
        if let userName {
            keychain.save(userName, for: .jellyfinUserName)
        } else {
            keychain.delete(.jellyfinUserName)
        }
        // the connect screen ran the server check, which set the name
        if let serverName {
            keychain.save(serverName, for: .jellyfinServerName)
        } else {
            keychain.delete(.jellyfinServerName)
        }
        self.client = client
        self.userID = userID
        self.userName = userName
        accountDisconnectFailed = false
    }

    /// Drops the sign-in in flight, so it ends any Jellyfin session it made and keeps no token (Cancel on the connect screens)
    func cancelConnect() {
        generation += 1
    }

    /// Plays the item from Jellyfin's stored position for the connected user, or from zero with fromStart
    func play(_ item: BaseItemDto, fromStart: Bool = false) async {
        await play(item, atTicks: fromStart ? 0 : item.userData?.playbackPositionTicks ?? 0)
    }

    /// Plays the item from the position, taking over the player of an item playing now, so the next episode or Try Again keeps the player open
    func play(_ item: BaseItemDto, atTicks ticks: Int) async {
        guard let service else { return }
        let previous = playback
        let session = PlaybackSession(service: service, item: item)
        playback = session
        if let previous { await end(previous) }
        // a close or another play during the previous item's stop report replaced this session before it started
        guard playback === session else { return }
        await session.start(atTicks: ticks)
    }

    /// The URL of one of the item's Jellyfin images (no token, as Jellyfin serves images without one), nil while disconnected
    func imageURL(itemID: String, type: ImageType, tag: String?, maxWidth: Int) -> URL? {
        var parameters = Paths.GetItemImageParameters()
        parameters.tag = tag
        parameters.maxWidth = maxWidth
        parameters.quality = 90
        return client?.url(with: Paths.getItemImage(itemID: itemID, imageType: type.rawValue, parameters: parameters))
    }

    /// Stops the item playing now and closes the player
    func stopPlayback() async {
        let session = playback
        playback = nil
        guard let session else { return }
        await end(session)
    }

    /// Stops the session, then refetches its item, so a play Jellyfin reports as played sets finishedPlay and joins watchedIDs (a failed fetch sets neither)
    private func end(_ session: PlaybackSession) async {
        await session.stop()
        // Jellyfin decides played from the stop report, so only the item fetched after it tells
        var played: BaseItemDto?
        if let id = session.item.id, let item = try? await service?.item(id: id), item.userData?.isPlayed == true {
            played = item
            watchedIDs.insert(id)
        }
        finishedPlay = played
        playbackEnded += 1
    }

    /// Adds the item to watchedIDs for a biinge Watched mark, or removes it for an unmark
    func setWatched(itemID: String, watched: Bool) {
        if watched {
            watchedIDs.insert(itemID)
        } else {
            watchedIDs.remove(itemID)
        }
    }

    /// Ends this device's session but keeps the user name in memory for the connect screen (the account stays connected in the API)
    func reconnect() async {
        await disconnect(keeping: userName ?? "")
    }

    /// Ends this device's session and forgets it, also when the server can't be reached, and disconnects the account in the API when given apiClient (keeping only Reconnect's prefill)
    func disconnect(apiClient: APIClient? = nil, keeping prefill: String? = nil) async {
        // forget locally first, so a slow or unreachable server can't keep the connection alive
        let ended = client
        let session = playback
        playback = nil
        generation += 1
        keychain.delete(.jellyfinServer)
        keychain.delete(.jellyfinUserID)
        keychain.delete(.jellyfinToken)
        keychain.delete(.jellyfinUserName)
        keychain.delete(.jellyfinServerName)
        client = nil
        userID = nil
        userName = nil
        serverName = nil
        // set with the forgetting, so the connect screen that appears next already sees it
        reconnectPrefill = prefill
        skippedConnect = false
        finishedPlay = nil
        watchedIDs = []
        isUnreachable = false
        firstPages = [:]
        genres = [:]
        // SDK 3.3.0 signOut() revokes the key, which needs an admin; ending the session works for any user
        await session?.stop()
        _ = try? await ended?.send(Paths.reportSessionEnded)
        // a failed call leaves the account connected, which the connect screens offer to retry; Log out passes no apiClient and leaves nothing to retry
        accountDisconnectFailed = if let apiClient { (try? await apiClient.disconnectJellyfin()) == nil } else { false }
    }

    /// Sends Disconnect's API call again, and clears accountDisconnectFailed once it goes through
    func retryAccountDisconnect(apiClient: APIClient) async {
        if (try? await apiClient.disconnectJellyfin()) != nil { accountDisconnectFailed = false }
    }

    /// Updates isUnreachable from a Jellyfin call's outcome (nil for a success; a 401, any other answer, a cancellation and a call from before a disconnect leave it alone)
    func record(_ error: (any Error)?, generation: Int) {
        // a call the replaced connection started says nothing about this one
        guard generation == self.generation else { return }
        // an equal write would still redraw every view that reads the flag
        if let error {
            if !isUnreachable, Self.isUnreachable(error) { isUnreachable = true }
        } else if isUnreachable {
            isUnreachable = false
        }
    }

    /// Whether the error says the server can't be reached (a transport error, or a 502, 503 or 504 from a proxy in front of it)
    static func isUnreachable(_ error: any Error) -> Bool {
        switch error {
        case let error as URLError:
            [.cannotFindHost, .cannotConnectToHost, .timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code)
        case Get.APIError.unacceptableStatusCode(let status):
            [502, 503, 504].contains(status)
        default:
            false
        }
    }

    /// Sends Jellyfin's public system info request, which needs no sign-in, and records its outcome (the Mac sidebar's Retry)
    func checkReachability() async {
        guard let client else { return }
        let started = generation
        do {
            _ = try await client.send(Paths.getPublicSystemInfo)
            record(nil, generation: started)
        } catch {
            record(error, generation: started)
        }
    }

    /// Disconnects and returns true when the error says Jellyfin revoked the token, otherwise leaves the connection alone
    func handleFailure(_ error: any Error) async -> Bool {
        guard Self.isRevoked(error) else { return false }
        await disconnect()
        return true
    }

    /// Whether the error is Jellyfin's 401 for a revoked or expired access token
    static func isRevoked(_ error: any Error) -> Bool {
        if case Get.APIError.unacceptableStatusCode(401) = error { return true }
        return false
    }

    /// This device's ID from the Keychain, which outlives a disconnect and a reinstall (the first run moves the UserDefaults value there, or a new UUID, and UserDefaults keeps it while the Keychain refuses the write)
    static func storedDeviceID(keychain: any KeychainStore = Keychain(), defaults: UserDefaults = .standard) -> String {
        // a stable device ID lets Jellyfin replace this device's session instead of piling up new ones
        if let stored = keychain.read(.jellyfinDeviceID) { return stored }
        let deviceID = defaults.string(forKey: "jellyfinDeviceID") ?? UUID().uuidString
        if keychain.save(deviceID, for: .jellyfinDeviceID) {
            defaults.removeObject(forKey: "jellyfinDeviceID")
        } else {
            defaults.set(deviceID, forKey: "jellyfinDeviceID")
        }
        return deviceID
    }

    private static func configuration(url: URL, accessToken: String?, deviceID: String) -> JellyfinClient.Configuration {
        JellyfinClient.Configuration(
            url: url,
            accessToken: accessToken,
            client: "Biinge",
            deviceName: DeviceInfo.deviceName,
            deviceID: deviceID,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        )
    }
}
