import Foundation
import Get
import JellyfinAPI
import Testing
@testable import Biinge

/// Answers the biinge connection endpoints and the Jellyfin sign-in from the scenario the running test sets, and records every request
final class JellyfinConnectProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var baseURL = "https://jellyfin.example.com"
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var failPut = false
    /// The status the API's DELETE of the connection answers
    nonisolated(unsafe) static var deleteStatus = 204
    /// Every request as "METHOD host path", in order (behind a lock, as the URLProtocol thread appends while a test reads)
    static var requests: [String] {
        get { lock.withLock { recorded } }
        set { lock.withLock { recorded = newValue } }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [String] = []
    /// The body of the last PUT to the API
    nonisolated(unsafe) static var putBody = Data()
    /// The status Jellyfin's playback start report answers
    nonisolated(unsafe) static var playingStatus = 204
    /// Each "METHOD path" here waits for its semaphore before it answers, so a test can act while the request is in flight
    nonisolated(unsafe) static var holds: [String: DispatchSemaphore] = [:]

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod, let host = url.host() else { return }
        Self.lock.withLock { Self.recorded.append("\(method) \(host) \(url.path)") }
        // the timeout keeps a failed test from blocking the session's thread for good
        _ = Self.holds["\(method) \(url.path)"]?.wait(timeout: .now() + 5)
        let status: Int
        let response: String
        switch (method, url.path) {
        case ("GET", "/api/v1/accounts/integrations/jellyfin/connection"):
            status = Self.statusCode
            response = status == 200 ? #"{"base_url": "\#(Self.baseURL)", "connected": false}"# : #"{"error": "not found"}"#
        case ("PUT", "/api/v1/accounts/integrations/jellyfin/connection"):
            // URLSession hands a body to the protocol as a stream
            var body = Data()
            if let stream = request.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    body.append(buffer, count: count)
                }
                stream.close()
            }
            Self.putBody = request.httpBody ?? body
            status = Self.failPut ? 422 : 200
            response = Self.failPut ? #"{"error": "Jellyfin rejected the username or password"}"# : #"{"base_url": "\#(Self.baseURL)", "connected": true, "username": "user"}"#
        case ("DELETE", "/api/v1/accounts/integrations/jellyfin/connection"):
            status = Self.deleteStatus
            response = status == 204 ? "" : #"{"error": "internal error"}"#
        case ("GET", "/System/Info/Public"):
            status = 200
            response = #"{"ServerName": "Living Room"}"#
        case ("POST", "/Sessions/Playing"):
            status = Self.playingStatus
            response = ""
        case ("POST", "/Users/AuthenticateByName"):
            status = 200
            response = #"{"AccessToken": "token", "User": {"Id": "user-id", "Name": "user"}}"#
        default:
            // the Jellyfin session end answers with no content
            status = 204
            response = ""
        }
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Answers every request to subtitles.example.com with a proxy's 503 (registered for URLSession.shared, which the subtitle download uses)
final class SubtitleUnavailableProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { request.url?.host() == "subtitles.example.com" }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let http = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct JellyfinConnectionTests {
    let configuration: URLSessionConfiguration
    let apiClient: Biinge.APIClient

    init() {
        JellyfinConnectProtocol.baseURL = "https://jellyfin.example.com"
        JellyfinConnectProtocol.statusCode = 200
        JellyfinConnectProtocol.failPut = false
        JellyfinConnectProtocol.deleteStatus = 204
        JellyfinConnectProtocol.playingStatus = 204
        JellyfinConnectProtocol.requests = []
        JellyfinConnectProtocol.putBody = Data()
        JellyfinConnectProtocol.holds = [:]
        configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JellyfinConnectProtocol.self]
        apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
    }

    @Test(arguments: ["http://media.example.com", "https://", "", "media.example.com"])
    func connectRejectsAnAddressWithoutHTTPS(server: String) async {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        // the Keychain may hold a live-check connection, so expect no change rather than no connection
        let wasConnected = connection.isConnected

        await #expect(throws: JellyfinConnectionError.notHTTPS) {
            try await connection.connect(server: server, user: "user", password: "password", apiClient: apiClient)
        }
        #expect(connection.isConnected == wasConnected)
        #expect(JellyfinConnectProtocol.requests.isEmpty)
    }

    @Test(arguments: ["http://media.example.com", "https://", "", "media.example.com"])
    func checkServerRejectsAnAddressWithoutHTTPS(address: String) async {
        JellyfinConnectProtocol.baseURL = address
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        await #expect(throws: JellyfinConnectionError.notHTTPS) {
            try await connection.checkServer(apiClient: apiClient)
        }
    }

    @Test func checkServerTakesTheAddressFromTheAPIAndTheNameFromJellyfin() async throws {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        let found = try await connection.checkServer(apiClient: apiClient)

        #expect(found.address == "https://jellyfin.example.com")
        #expect(found.name == "Living Room")
        #expect(JellyfinConnectProtocol.requests == [
            "GET api.example.com /api/v1/accounts/integrations/jellyfin/connection",
            "GET jellyfin.example.com /System/Info/Public",
        ])
    }

    @Test func checkServerReadsA404AsNoJellyfinServer() async {
        JellyfinConnectProtocol.statusCode = 404
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        await #expect(throws: JellyfinConnectionError.noServer) {
            try await connection.checkServer(apiClient: apiClient)
        }
        #expect(JellyfinConnectProtocol.requests == ["GET api.example.com /api/v1/accounts/integrations/jellyfin/connection"])
    }

    @Test func checkServerPassesAnyOtherAPIErrorThrough() async throws {
        JellyfinConnectProtocol.statusCode = 500
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        let error = try #require(await #expect(throws: Biinge.APIError.self) {
            try await connection.checkServer(apiClient: apiClient)
        })
        guard case .server(status: 500) = error else {
            Issue.record("expected the API's 500, got \(error)")
            return
        }
    }

    @Test func theConnectionStatusDecodesWithoutAUsernameWhileNotConnected() async throws {
        let status = try await apiClient.jellyfinConnection()

        #expect(status.baseURL == "https://jellyfin.example.com")
        #expect(!status.connected)
        #expect(status.username == nil)
    }

    @Test func connectJellyfinPutsTheCredentialsAndReadsTheConnectedStatus() async throws {
        let status = try await apiClient.connectJellyfin(JellyfinConnectionRequest(username: "user", password: "secret"))

        #expect(JellyfinConnectProtocol.requests == ["PUT api.example.com /api/v1/accounts/integrations/jellyfin/connection"])
        let body = try JSONSerialization.jsonObject(with: JellyfinConnectProtocol.putBody) as? [String: String]
        #expect(body == ["username": "user", "password": "secret"])
        #expect(status.connected)
        #expect(status.username == "user")
    }

    @Test func anUnmarkTakesTheItemOutOfWatchedIDs() {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        connection.setWatched(itemID: "m", watched: true)
        connection.setWatched(itemID: "e", watched: true)
        connection.setWatched(itemID: "m", watched: false)

        // Home shows the unmarked item again
        #expect(connection.watchedIDs == ["e"])
    }

    @Test func connectSignsInOnTheDeviceBeforeTheAPIAndKeepsNothingWhenTheAPIFails() async throws {
        JellyfinConnectProtocol.failPut = true
        let keychain = Keychain()
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        // the Keychain may hold a live-check connection, so expect no change rather than no connection
        let wasConnected = connection.isConnected
        let storedToken = keychain.read(.jellyfinToken)

        await #expect(throws: Biinge.APIError.self) {
            try await connection.connect(server: "https://jellyfin.example.com", user: "user", password: "secret", apiClient: apiClient)
        }

        #expect(JellyfinConnectProtocol.requests == [
            "GET jellyfin.example.com /System/Info/Public",
            "POST jellyfin.example.com /Users/AuthenticateByName",
            "PUT api.example.com /api/v1/accounts/integrations/jellyfin/connection",
            // the new device session ends, as the account didn't connect
            "POST jellyfin.example.com /Sessions/Logout",
        ])
        let body = try JSONSerialization.jsonObject(with: JellyfinConnectProtocol.putBody) as? [String: String]
        #expect(body == ["username": "user", "password": "secret"])
        #expect(connection.isConnected == wasConnected)
        #expect(keychain.read(.jellyfinToken) == storedToken)
    }

    @Test func cancelDuringTheServerCheckStopsBeforeASessionExists() async throws {
        let hold = DispatchSemaphore(value: 0)
        JellyfinConnectProtocol.holds["GET /System/Info/Public"] = hold
        let keychain = Keychain()
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        // the Keychain may hold a live-check connection, so expect no change rather than no connection
        let wasConnected = connection.isConnected
        let storedToken = keychain.read(.jellyfinToken)

        let attempt = Task { try await connection.connect(server: "https://jellyfin.example.com", user: "user", password: "secret", apiClient: apiClient) }
        try await Self.waitForRequest("GET jellyfin.example.com /System/Info/Public")
        connection.cancelConnect()
        hold.signal()
        try await attempt.value

        // no sign-in, so no session to end and no credentials for the API
        #expect(JellyfinConnectProtocol.requests == ["GET jellyfin.example.com /System/Info/Public"])
        #expect(connection.isConnected == wasConnected)
        #expect(keychain.read(.jellyfinToken) == storedToken)
    }

    @Test func cancelDuringSignInEndsTheNewSessionAndNeverConnectsTheAccount() async throws {
        let hold = DispatchSemaphore(value: 0)
        JellyfinConnectProtocol.holds["POST /Users/AuthenticateByName"] = hold
        let keychain = Keychain()
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        // the Keychain may hold a live-check connection, so expect no change rather than no connection
        let wasConnected = connection.isConnected
        let storedToken = keychain.read(.jellyfinToken)

        let attempt = Task { try await connection.connect(server: "https://jellyfin.example.com", user: "user", password: "secret", apiClient: apiClient) }
        try await Self.waitForRequest("POST jellyfin.example.com /Users/AuthenticateByName")
        connection.cancelConnect()
        hold.signal()
        try await attempt.value

        #expect(JellyfinConnectProtocol.requests == [
            "GET jellyfin.example.com /System/Info/Public",
            "POST jellyfin.example.com /Users/AuthenticateByName",
            // the late sign-in's session ends, and the API never gets the credentials
            "POST jellyfin.example.com /Sessions/Logout",
        ])
        #expect(connection.isConnected == wasConnected)
        #expect(keychain.read(.jellyfinToken) == storedToken)
    }

    @Test func cancelDuringTheAPIConnectEndsTheNewSessionAndKeepsNothing() async throws {
        let hold = DispatchSemaphore(value: 0)
        JellyfinConnectProtocol.holds["PUT /api/v1/accounts/integrations/jellyfin/connection"] = hold
        let keychain = Keychain()
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        // the Keychain may hold a live-check connection, so expect no change rather than no connection
        let wasConnected = connection.isConnected
        let storedToken = keychain.read(.jellyfinToken)

        let attempt = Task { try await connection.connect(server: "https://jellyfin.example.com", user: "user", password: "secret", apiClient: apiClient) }
        try await Self.waitForRequest("PUT api.example.com /api/v1/accounts/integrations/jellyfin/connection")
        connection.cancelConnect()
        hold.signal()
        try await attempt.value

        #expect(JellyfinConnectProtocol.requests == [
            "GET jellyfin.example.com /System/Info/Public",
            "POST jellyfin.example.com /Users/AuthenticateByName",
            "PUT api.example.com /api/v1/accounts/integrations/jellyfin/connection",
            // the device session ends, and the account stays connected in the API for other devices
            "POST jellyfin.example.com /Sessions/Logout",
        ])
        #expect(connection.isConnected == wasConnected)
        #expect(keychain.read(.jellyfinToken) == storedToken)
    }

    @Test func aFailedServerCheckKeepsTheAddressTheAPIReported() async {
        JellyfinConnectProtocol.baseURL = "http://media.example.com"
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        await #expect(throws: JellyfinConnectionError.notHTTPS) {
            try await connection.checkServer(apiClient: apiClient)
        }
        #expect(connection.checkedAddress == "http://media.example.com")
    }

    // skipped when the Keychain holds a live-check connection, which this test would otherwise replace,
    // and on the unsigned iOS and tvOS simulator runs, whose Keychain rejects writes
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func connectKeepsTheSessionOnceTheAPIConnects() async throws {
        let keychain = Keychain()
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
            keychain.delete(.jellyfinUserName)
            keychain.delete(.jellyfinServerName)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        // the connect screen checks the server first, which names it
        _ = try await connection.checkServer(apiClient: apiClient)
        try await connection.connect(server: "https://jellyfin.example.com", user: "user", password: "secret", apiClient: apiClient)

        #expect(connection.isConnected)
        #expect(connection.userName == "user")
        #expect(connection.client?.configuration.deviceID == "test")
        #expect(keychain.read(.jellyfinServer) == "https://jellyfin.example.com")
        #expect(keychain.read(.jellyfinServerName) == "Living Room")
        #expect(keychain.read(.jellyfinToken) == "token")
        #expect(!JellyfinConnectProtocol.requests.contains("POST jellyfin.example.com /Sessions/Logout"))
    }

    @Test func isRevokedForA401() {
        #expect(JellyfinConnection.isRevoked(Get.APIError.unacceptableStatusCode(401)))
    }

    @Test(arguments: [
        Get.APIError.unacceptableStatusCode(403),
        Get.APIError.unacceptableStatusCode(500),
        URLError(.notConnectedToInternet),
        JellyfinConnectionError.notJellyfin,
    ] as [any Error])
    func isRevokedIsFalseForAnyOtherError(error: any Error) {
        #expect(!JellyfinConnection.isRevoked(error))
    }

    @Test(arguments: [
        URLError(.cannotFindHost),
        URLError(.cannotConnectToHost),
        URLError(.timedOut),
        URLError(.networkConnectionLost),
        URLError(.notConnectedToInternet),
        Get.APIError.unacceptableStatusCode(502),
        Get.APIError.unacceptableStatusCode(503),
        Get.APIError.unacceptableStatusCode(504),
    ] as [any Error])
    func aFailureToReachTheServerMarksItUnreachableUntilASuccess(error: any Error) {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        connection.record(error, generation: connection.generation)
        #expect(connection.isUnreachable)

        connection.record(nil, generation: connection.generation)
        #expect(!connection.isUnreachable)
    }

    @Test(arguments: [
        Get.APIError.unacceptableStatusCode(401),
        Get.APIError.unacceptableStatusCode(404),
        Get.APIError.unacceptableStatusCode(500),
        URLError(.cancelled),
        CancellationError(),
    ] as [any Error])
    func anAnswerOrACancellationLeavesReachabilityAlone(error: any Error) {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        connection.record(error, generation: connection.generation)
        #expect(!connection.isUnreachable)

        connection.record(URLError(.timedOut), generation: connection.generation)
        connection.record(error, generation: connection.generation)
        #expect(connection.isUnreachable)
    }

    @Test func theServiceReportsEachCallsOutcomeToTheConnection() async throws {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        let client = try JellyfinClient(
            configuration: .init(url: #require(URL(string: "https://jellyfin.example.com")), client: "Biinge", deviceName: "Test", deviceID: "test", version: "1"),
            sessionConfiguration: configuration
        )
        let service = JellyfinAPIService(client: client, userID: "user", connection: connection)

        JellyfinConnectProtocol.playingStatus = 503
        await #expect(throws: Get.APIError.self) { try await service.reportStart(PlaybackStateInfo()) }
        #expect(connection.isUnreachable)

        JellyfinConnectProtocol.playingStatus = 204
        try await service.reportStart(PlaybackStateInfo())
        #expect(!connection.isUnreachable)
    }

    @Test func handleFailureLeavesTheConnectionForAnyOtherError() async {
        let connection = JellyfinConnection(deviceID: { "test" })
        // the Keychain may hold a live-check connection, so expect no change rather than no connection
        let wasConnected = connection.isConnected

        #expect(await !connection.handleFailure(URLError(.notConnectedToInternet)))
        #expect(connection.isConnected == wasConnected)
    }

    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func handleFailureDisconnectsForA401() async throws {
        let keychain = Keychain()
        keychain.save("https://jellyfin.example.com", for: .jellyfinServer)
        keychain.save("user-id", for: .jellyfinUserID)
        keychain.save("token", for: .jellyfinToken)
        keychain.save("user", for: .jellyfinUserName)
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
            keychain.delete(.jellyfinUserName)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        try #require(connection.isConnected)
        #expect(connection.client?.configuration.deviceID == "test")

        #expect(await connection.handleFailure(Get.APIError.unacceptableStatusCode(401)))
        #expect(!connection.isConnected)
        #expect(connection.userName == nil)
        #expect(keychain.read(.jellyfinServer) == nil)
        #expect(keychain.read(.jellyfinUserID) == nil)
        #expect(keychain.read(.jellyfinToken) == nil)
        #expect(keychain.read(.jellyfinUserName) == nil)
    }

    // runs on the simulators too, whose Keychain holds nothing; skipped when a live-check connection would be forgotten
    @Test(.enabled(if: Keychain().read(.jellyfinToken) == nil, "needs a Keychain without a stored Jellyfin connection"))
    func disconnectSendsDELETEAndClearsNotNow() async {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        connection.skippedConnect = true
        connection.setWatched(itemID: "m", watched: true)

        await connection.disconnect(apiClient: apiClient)

        #expect(!connection.skippedConnect)
        #expect(connection.watchedIDs.isEmpty)
        #expect(JellyfinConnectProtocol.requests == ["DELETE api.example.com /api/v1/accounts/integrations/jellyfin/connection"])
    }

    // runs on the simulators too, like disconnectSendsDELETEAndClearsNotNow
    @Test(.enabled(if: Keychain().read(.jellyfinToken) == nil, "needs a Keychain without a stored Jellyfin connection"))
    func aFailedAccountDisconnectStaysFlaggedUntilARetryGoesThrough() async {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        JellyfinConnectProtocol.deleteStatus = 500

        await connection.disconnect(apiClient: apiClient)
        #expect(connection.accountDisconnectFailed)

        JellyfinConnectProtocol.deleteStatus = 204
        await connection.retryAccountDisconnect(apiClient: apiClient)

        #expect(!connection.accountDisconnectFailed)
        #expect(JellyfinConnectProtocol.requests == [
            "DELETE api.example.com /api/v1/accounts/integrations/jellyfin/connection",
            "DELETE api.example.com /api/v1/accounts/integrations/jellyfin/connection",
        ])
    }

    // runs on the simulators too, like disconnectSendsDELETEAndClearsNotNow
    @Test(.enabled(if: Keychain().read(.jellyfinToken) == nil, "needs a Keychain without a stored Jellyfin connection"))
    func theServerNameOutlastsNotNowUntilADisconnect() async throws {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        _ = try await connection.checkServer(apiClient: apiClient)
        connection.skippedConnect = true

        #expect(connection.serverName == "Living Room")
        await connection.disconnect()
        #expect(connection.serverName == nil)
    }

    // runs on the simulators too, like disconnectSendsDELETEAndClearsNotNow
    @Test(.enabled(if: Keychain().read(.jellyfinToken) == nil, "needs a Keychain without a stored Jellyfin connection"))
    func reconnectSendsNoDELETE() async {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })

        await connection.reconnect()

        #expect(JellyfinConnectProtocol.requests.isEmpty)
    }

    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func disconnectEndsTheSessionAndDisconnectsTheAccount() async throws {
        let keychain = Keychain()
        keychain.save("https://jellyfin.example.com", for: .jellyfinServer)
        keychain.save("user-id", for: .jellyfinUserID)
        keychain.save("token", for: .jellyfinToken)
        keychain.save("user", for: .jellyfinUserName)
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
            keychain.delete(.jellyfinUserName)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        try #require(connection.isConnected)
        connection.skippedConnect = true

        await connection.disconnect(apiClient: apiClient)

        #expect(!connection.isConnected)
        #expect(!connection.skippedConnect)
        #expect(keychain.read(.jellyfinToken) == nil)
        #expect(JellyfinConnectProtocol.requests == [
            "POST jellyfin.example.com /Sessions/Logout",
            "DELETE api.example.com /api/v1/accounts/integrations/jellyfin/connection",
        ])
    }

    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func reconnectEndsOnlyTheDeviceSessionAndKeepsTheUser() async throws {
        let keychain = Keychain()
        keychain.save("https://jellyfin.example.com", for: .jellyfinServer)
        keychain.save("user-id", for: .jellyfinUserID)
        keychain.save("token", for: .jellyfinToken)
        keychain.save("user", for: .jellyfinUserName)
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
            keychain.delete(.jellyfinUserName)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        try #require(connection.isConnected)

        await connection.reconnect()

        #expect(!connection.isConnected)
        #expect(connection.reconnectPrefill == "user")
        #expect(keychain.read(.jellyfinToken) == nil)
        #expect(JellyfinConnectProtocol.requests == ["POST jellyfin.example.com /Sessions/Logout"])
    }

    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func disconnectClearsTheReconnectPrefill() async throws {
        let keychain = Keychain()
        keychain.save("https://jellyfin.example.com", for: .jellyfinServer)
        keychain.save("user-id", for: .jellyfinUserID)
        keychain.save("token", for: .jellyfinToken)
        keychain.save("user", for: .jellyfinUserName)
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
            keychain.delete(.jellyfinUserName)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        try #require(connection.isConnected)
        await connection.reconnect()
        try #require(connection.reconnectPrefill != nil)

        await connection.disconnect()
        #expect(connection.reconnectPrefill == nil)
    }

    /// Waits up to 5 s for the request to reach the stub protocol
    static func waitForRequest(_ request: String) async throws {
        var waited = 0
        while !JellyfinConnectProtocol.requests.contains(request), waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        try #require(JellyfinConnectProtocol.requests.contains(request))
    }

    /// True when the Keychain holds no Jellyfin token and accepts a write
    nonisolated static func keychainIsFree() -> Bool {
        let keychain = Keychain()
        guard keychain.read(.jellyfinToken) == nil else { return false }
        keychain.save("probe", for: .jellyfinToken)
        defer { keychain.delete(.jellyfinToken) }
        return keychain.read(.jellyfinToken) != nil
    }
}

// the reachability tests share the suite's stub and its serialized runs
extension JellyfinConnectionTests {
    @Test func aSubtitle503MarksTheServerUnreachable() async throws {
        URLProtocol.registerClass(SubtitleUnavailableProtocol.self)
        defer { URLProtocol.unregisterClass(SubtitleUnavailableProtocol.self) }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        let client = try JellyfinClient(
            configuration: .init(url: #require(URL(string: "https://subtitles.example.com")), client: "Biinge", deviceName: "Test", deviceID: "test", version: "1"),
            sessionConfiguration: configuration
        )
        let service = JellyfinAPIService(client: client, userID: "user", connection: connection, generation: connection.generation)

        await #expect(throws: Get.APIError.self) { try await service.subtitleFile(deliveryURL: "/Videos/1/1/Subtitles/2/0/Stream.srt?api_key=key") }
        #expect(connection.isUnreachable)
    }

    // runs on the simulators too, like disconnectSendsDELETEAndClearsNotNow
    @Test(.enabled(if: Keychain().read(.jellyfinToken) == nil, "needs a Keychain without a stored Jellyfin connection"))
    func aCallTheReplacedConnectionStartedLeavesTheNewOnesStateAlone() async throws {
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        let client = try JellyfinClient(
            configuration: .init(url: #require(URL(string: "https://jellyfin.example.com")), client: "Biinge", deviceName: "Test", deviceID: "test", version: "1"),
            sessionConfiguration: configuration
        )
        let service = JellyfinAPIService(client: client, userID: "user", connection: connection, generation: connection.generation)
        let held = DispatchSemaphore(value: 0)
        JellyfinConnectProtocol.holds["POST /Sessions/Playing"] = held
        let report = Task { try await service.reportStart(PlaybackStateInfo()) }
        try await Self.waitForRequest("POST jellyfin.example.com /Sessions/Playing")

        // the connection is replaced while the report is in flight, and a call of the new one fails to reach its server
        await connection.disconnect()
        connection.record(URLError(.timedOut), generation: connection.generation)
        held.signal()
        try await report.value

        // the old report's success says nothing about the new server
        #expect(connection.isUnreachable)
    }
}
