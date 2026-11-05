import Foundation
import Testing
@testable import Biinge

/// Answers the biinge Up Next endpoint with body, or with a server error while the running test sets fails, and never answers while it sets hangs
final class UpNextProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var body = "{}"
    nonisolated(unsafe) static var fails = false
    nonisolated(unsafe) static var hangs = false

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard !Self.hangs, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: Self.fails ? 500 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.fails ? #"{"error": "internal error"}"# : Self.body).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// every test needs Jellyfin disconnected, so the store loads the tracked queue alone; skipped when the Keychain holds a live-check connection
@MainActor
@Suite(.serialized, .enabled(if: Keychain().read(.jellyfinToken) == nil, "needs a Keychain without a stored Jellyfin connection"))
struct UpNextStoreTests {
    private let store: UpNextStore

    init() {
        UpNextProtocol.body = "{}"
        UpNextProtocol.fails = false
        UpNextProtocol.hangs = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpNextProtocol.self]
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
        store = UpNextStore(apiClient: apiClient, connection: JellyfinConnection(sessionConfiguration: configuration, deviceID: { "test" }))
    }

    @Test func aTrackedQueueShowsWithoutJellyfin() async {
        UpNextProtocol.body = #"{"movies": [{"id": 4}]}"#

        await store.load()

        #expect(store.sections.map(\.title) == ["Movies"])
        #expect(store.state == nil)
        #expect(store.loadError == nil)
        #expect(!store.isLoading)
    }

    @Test func anEmptyQueueIsLoadingUntilItLandsThenEmpty() async {
        #expect(store.state == .loading)

        await store.load()

        #expect(store.upNext != nil)
        #expect(store.state == .empty)
    }

    @Test func aFailedFirstLoadShowsItsErrorInsteadOfTheEmptyState() async {
        UpNextProtocol.fails = true

        await store.load()

        #expect(store.upNext == nil)
        #expect(store.loadError != nil)
        guard case .failed = store.state else {
            Issue.record("expected the failed state, got \(String(describing: store.state))")
            return
        }
    }

    @Test func aFailedRefreshKeepsTheQueueAndASuccessClearsTheError() async {
        UpNextProtocol.body = #"{"movies": [{"id": 4}]}"#
        await store.load()

        UpNextProtocol.fails = true
        await store.load()

        #expect(store.loadError != nil)
        #expect(store.sections.map(\.title) == ["Movies"])
        #expect(store.state == nil)

        UpNextProtocol.fails = false
        await store.load()

        #expect(store.loadError == nil)
    }

    @Test func closingTheSheetMidLoadIsNoFailure() async {
        UpNextProtocol.hangs = true
        let load = Task { await store.load() }

        load.cancel()
        await load.value

        #expect(store.loadError == nil)
        #expect(store.upNext == nil)
        #expect(!store.isLoading)
    }
}
