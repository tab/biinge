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
        try await preservingSession {
            let authManager = AuthManager()
            let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: authManager, configuration: configuration)

            try await authManager.login(using: apiClient, email: "tom@example.com", password: "password")

            #expect(authManager.isAuthenticated)
            #expect(authManager.connectsJellyfinFirst)
        }
    }

    @Test func theLoginScreensHookRunsBeforeTheUserSwapsTheRoot() async throws {
        try await preservingSession {
            let authManager = AuthManager()
            let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: authManager, configuration: configuration)
            var wasAuthenticated = true

            try await authManager.login(using: apiClient, email: "tom@example.com", password: "password") {
                wasAuthenticated = authManager.isAuthenticated
            }

            #expect(!wasAuthenticated)
            #expect(authManager.isAuthenticated)
        }
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

    /// Puts the simulator's stored biinge tokens back after the body, as the tests share the app's Keychain
    func preservingSession(_ body: () async throws -> Void) async throws {
        let keychain = Keychain()
        let stored = [KeychainKey.accessToken, .refreshToken].map { ($0, keychain.read($0)) }
        defer {
            for (key, value) in stored {
                if let value { keychain.save(value, for: key) } else { keychain.delete(key) }
            }
        }
        try await body()
    }
}
