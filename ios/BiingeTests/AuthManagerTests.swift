import Foundation
import Testing
@testable import Biinge

/// Answers the biinge login with a token pair and every other request with the current user
final class AuthStubProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        let response = url.path == "/api/v1/users/sessions"
            ? #"{"access_token": "access", "refresh_token": "refresh"}"#
            : #"{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "login": "tom", "email": "tom@example.com", "appearance": "system"}"#
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct AuthManagerTests {
    let configuration: URLSessionConfiguration

    init() {
        configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubProtocol.self]
    }

    @Test func aLoginInThisLaunchOpensConnectJellyfinFirst() async throws {
        let keychain = KeychainStub()
        let authManager = AuthManager(keychain: keychain)
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: authManager, configuration: configuration)

        try await authManager.login(using: apiClient, email: "tom@example.com", password: "password")

        #expect(authManager.isAuthenticated)
        #expect(authManager.connectsJellyfinFirst)
        #expect(keychain.read(.accessToken) == "access")
        #expect(keychain.read(.refreshToken) == "refresh")

        authManager.logout()

        #expect(keychain.read(.accessToken) == nil)
        #expect(keychain.read(.refreshToken) == nil)
    }

    @Test func aStoredSessionIsReadAtLaunch() {
        let keychain = KeychainStub()
        keychain.items = [.accessToken: "stored-access", .refreshToken: "stored-refresh"]

        let authManager = AuthManager(keychain: keychain)

        #expect(authManager.accessToken == "stored-access")
    }

    @Test func theLoginScreensHookRunsBeforeTheUserSwapsTheRoot() async throws {
        let authManager = AuthManager(keychain: KeychainStub())
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: authManager, configuration: configuration)
        var wasAuthenticated = true

        try await authManager.login(using: apiClient, email: "tom@example.com", password: "password") {
            wasAuthenticated = authManager.isAuthenticated
        }

        #expect(!wasAuthenticated)
        #expect(authManager.isAuthenticated)
    }

    @Test func aFailedLoginRingsTheFieldsAtFault() {
        #expect(LoginFailure(email: "tom@example.com", password: "password") == nil)
        #expect(LoginFailure(email: "", password: "password")?.fields == [.email])
        #expect(LoginFailure(email: "tom@example.com", password: "short")?.fields == [.password])
        #expect(LoginFailure(email: "", password: "")?.fields == [.email, .password])
        // the API won't say which of the two is wrong
        #expect(LoginFailure(APIError.unauthorized).fields == [.email, .password])
        #expect(LoginFailure(APIError.badRequest("empty password")).fields == [.password])
        #expect(LoginFailure(APIError.badRequest("Key: 'LoginRequestSerializer.Email' Error:Field validation for 'Email' failed")).fields == [.email])
        #expect(LoginFailure(APIError.network).fields.isEmpty)
        #expect(LoginFailure(APIError.network).message == APIError.network.errorDescription)
    }
}
