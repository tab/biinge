import Foundation
import Testing
@testable import Biinge

// the flow drives JellyfinConnectProtocol's scenarios, so these tests share JellyfinConnectionTests' serialized runs
extension JellyfinConnectionTests {
    @Test func aCheckThatFindsTheServerShowsTheForm() async {
        let flow = ConnectFlow(connection: JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" }), apiClient: apiClient)
        #expect(flow.step == .checking)

        await flow.check()

        #expect(flow.step == .signIn)
        #expect(flow.server == "https://jellyfin.example.com")
        #expect(flow.serverName == "Living Room")
    }

    @Test func aBiingeWithoutJellyfinShowsNoServer() async {
        JellyfinConnectProtocol.statusCode = 404
        let flow = ConnectFlow(connection: JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" }), apiClient: apiClient)

        await flow.check()

        #expect(flow.step == .noServer)
    }

    @Test func anUnreachableServerIsNamedByTheAddressTheAPIReported() async {
        JellyfinConnectProtocol.baseURL = "http://media.example.com"
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        let flow = ConnectFlow(connection: connection, apiClient: apiClient)

        await flow.check()

        #expect(flow.step == .unreachable(JellyfinConnectionError.notHTTPS.localizedDescription))
        #expect(flow.server == "http://media.example.com")
        // the Keychain may hold a live-check connection's server name, which names it before the host does
        #expect(flow.serverName == connection.serverName ?? "media.example.com")
    }

    @Test func anAPIThatCantAnswerLeavesNoAddressToName() async {
        JellyfinConnectProtocol.statusCode = 500
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        let flow = ConnectFlow(connection: connection, apiClient: apiClient)

        await flow.check()

        guard case .unreachable = flow.step else {
            Issue.record("expected Unreachable, got \(flow.step)")
            return
        }
        #expect(flow.server.isEmpty)
        // the Keychain may hold a live-check connection's server name, which names it first
        #expect(flow.serverName == connection.serverName ?? "the server")
    }

    @Test func aCheckTheScreenLeftChangesNothing() async {
        let flow = ConnectFlow(connection: JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" }), apiClient: apiClient)

        let check = Task { await flow.check() }
        check.cancel()
        await check.value

        #expect(flow.step == .checking)
    }

    @Test func theAutoconnectVariableSignsInOnceTheFormShows() async throws {
        setenv("JELLYFIN_AUTOCONNECT", "1", 1)
        defer { unsetenv("JELLYFIN_AUTOCONNECT") }
        let flow = ConnectFlow(connection: JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" }), apiClient: apiClient)
        // the rejected sign-in keeps nothing in the Keychain
        JellyfinConnectProtocol.failPut = true
        flow.user = "user"
        flow.password = "secret"

        await flow.check()
        try await Self.waitForRequest("PUT api.example.com /api/v1/accounts/integrations/jellyfin/connection")
        var waited = 0
        while flow.errorMessage == nil, waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }

        #expect(flow.errorMessage == "Jellyfin rejected the username or password")
        #expect(flow.step == .signIn)
    }

    @Test func connectRunsOnlyFromTheForm() async {
        let flow = ConnectFlow(connection: JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" }), apiClient: apiClient)

        await flow.connect()

        #expect(flow.step == .checking)
        #expect(JellyfinConnectProtocol.requests.isEmpty)
    }

    @Test func aFailedSignInReturnsToTheFormWithItsErrorAndTheUserKept() async {
        let flow = ConnectFlow(connection: JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" }), apiClient: apiClient)
        await flow.check()
        JellyfinConnectProtocol.failPut = true
        flow.user = "user"
        flow.password = "secret"

        await flow.connect()

        #expect(flow.step == .signIn)
        #expect(flow.errorMessage == "Jellyfin rejected the username or password")
        #expect(flow.user == "user")
    }

    @Test func cancelReturnsToTheFormAndTheDroppedSignInChangesNothing() async throws {
        let flow = ConnectFlow(connection: JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" }), apiClient: apiClient)
        await flow.check()
        JellyfinConnectProtocol.failPut = true
        let hold = DispatchSemaphore(value: 0)
        JellyfinConnectProtocol.holds["PUT /api/v1/accounts/integrations/jellyfin/connection"] = hold
        flow.user = "user"
        flow.password = "secret"

        let attempt = Task { await flow.connect() }
        try await Self.waitForRequest("PUT api.example.com /api/v1/accounts/integrations/jellyfin/connection")
        #expect(flow.step == .connecting)
        flow.cancel()
        #expect(flow.step == .signIn)
        hold.signal()
        await attempt.value

        // the dropped sign-in's failure lands after Cancel and leaves the form alone
        #expect(flow.step == .signIn)
        #expect(flow.errorMessage == nil)
    }

    // skipped like connectKeepsTheSessionOnceTheAPIConnects, for the same Keychain reasons
    @Test(.enabled(if: Self.keychainIsFree(), "needs a writable Keychain without a stored Jellyfin connection"))
    func aSignInThatLandsStaysOnConnectingUntilTheScreenGivesWay() async {
        let keychain = Keychain()
        defer {
            keychain.delete(.jellyfinServer)
            keychain.delete(.jellyfinUserID)
            keychain.delete(.jellyfinToken)
            keychain.delete(.jellyfinUserName)
            keychain.delete(.jellyfinServerName)
        }
        let connection = JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" })
        let flow = ConnectFlow(connection: connection, apiClient: apiClient)
        await flow.check()
        flow.user = "user"
        flow.password = "secret"

        await flow.connect()

        #expect(flow.step == .connecting)
        #expect(flow.errorMessage == nil)
        #expect(connection.isConnected)
    }
}
