import Foundation
import Testing
@testable import Biinge

/// Answers the biinge login with the status and body the running test sets, holding the answer back while the test sets held, and counts the logins sent
final class LoginFlowProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var status = 401
    nonisolated(unsafe) static var body = #"{"error": "unauthorized"}"#
    /// The logins sent (behind a lock, as the URLProtocol thread counts while a test reads)
    static var logins: Int {
        get { lock.withLock { sent } }
        set { lock.withLock { sent = newValue } }
    }
    /// Set while every login waits to answer, so a test can act while one is in flight (behind the lock too)
    static var held: Bool {
        get { lock.withLock { holding } }
        set { lock.withLock { holding = newValue } }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sent = 0
    nonisolated(unsafe) private static var holding = false

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        Self.lock.withLock { Self.sent += 1 }
        response = (http, Data(Self.body.utf8))
        answer()
    }

    override func stopLoading() {}

    /// The answer startLoading prepared
    private var response: (http: HTTPURLResponse, body: Data)?

    /// Answers once the test releases the logins, checking again on this protocol's run loop so a second login can still arrive meanwhile
    @objc private func answer() {
        guard let response else { return }
        if Self.held {
            perform(#selector(answer), with: nil, afterDelay: 0.01, inModes: [.common])
            return
        }
        client?.urlProtocol(self, didReceive: response.http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
@Suite(.serialized)
struct LoginFlowTests {
    private let flow: LoginFlow

    init() {
        LoginFlowProtocol.status = 401
        LoginFlowProtocol.body = #"{"error": "unauthorized"}"#
        LoginFlowProtocol.logins = 0
        LoginFlowProtocol.held = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginFlowProtocol.self]
        let authManager = AuthManager()
        let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: authManager, configuration: configuration)
        flow = LoginFlow(authManager: authManager, apiClient: apiClient)
    }

    @Test func aFormThatCantBeSentFailsWithoutALogin() async {
        // the email is trimmed before the check, so spaces alone are empty
        flow.email = "   "
        flow.password = "short"

        await flow.submit()

        #expect(flow.failure?.fields == [.email, .password])
        #expect(flow.failures == 1)
        #expect(LoginFlowProtocol.logins == 0)
    }

    @Test func rejectedCredentialsRingBothFieldsAndFreeTheButton() async {
        flow.email = "tom@example.com"
        flow.password = "password"

        await flow.submit()

        #expect(flow.failure == LoginFailure(APIError.unauthorized))
        #expect(flow.failures == 1)
        #expect(!flow.isSubmitting)
        #expect(!flow.isDone)
        #expect(LoginFlowProtocol.logins == 1)
    }

    @Test func aSecondSubmitWhileOneRunsSendsNoSecondLogin() async throws {
        LoginFlowProtocol.held = true
        flow.email = "tom@example.com"
        flow.password = "password"

        let first = Task { await flow.submit() }
        var waited = 0
        while LoginFlowProtocol.logins == 0, waited < 500 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        try #require(flow.isSubmitting)
        let second = Task { await flow.submit() }
        // a second login would have reached the stub by now, as the first one did
        try await Task.sleep(for: .milliseconds(200))
        LoginFlowProtocol.held = false
        await first.value
        await second.value

        #expect(LoginFlowProtocol.logins == 1)
        #expect(flow.failures == 1)
    }

    @Test func aValidationMessageRingsTheFieldItNames() async {
        LoginFlowProtocol.status = 400
        LoginFlowProtocol.body = #"{"error": "empty password"}"#
        flow.email = "tom@example.com"
        flow.password = "password"

        await flow.submit()

        #expect(flow.failure == LoginFailure(message: "empty password", fields: [.password]))
    }
}

// a login stores the session's tokens in the Keychain, so this test shares AuthManagerTests' serialized Keychain runs
extension AuthManagerTests {
    @Test func aLoginThatLandsLocksTheFormAndLeavesNoFailure() async throws {
        try await preservingSession {
            let authManager = AuthManager()
            let apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: authManager, configuration: configuration)
            let flow = LoginFlow(authManager: authManager, apiClient: apiClient)
            flow.failure = LoginFailure(APIError.unauthorized)
            flow.email = " tom@example.com "
            flow.password = "password"

            await flow.submit()

            #expect(flow.isDone)
            #expect(!flow.isSubmitting)
            #expect(flow.failure == nil)
            #expect(flow.failures == 0)
            #expect(authManager.isAuthenticated)
        }
    }
}
