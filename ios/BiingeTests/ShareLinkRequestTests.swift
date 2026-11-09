import Foundation
import Testing
@testable import Biinge

/// Answers POST /shares with a share link, or with the error status the running test sets
final class ShareProtocol: URLProtocol {
    // shortcut: shared scenario state, so the suite runs serialized; key it by host if these tests need to run in parallel
    nonisolated(unsafe) static var status = 201
    /// Every request as "METHOD path", in order
    nonisolated(unsafe) static var requests: [String] = []
    /// The body of the last request, which URLSession hands the protocol as a stream
    nonisolated(unsafe) static var body: Data?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return }
        Self.requests.append("\(method) \(url.path)")
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 { data.append(buffer, count: count) }
            Self.body = data
        }
        let body = Self.status == 201
            ? #"{"id": "6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60", "url": "https://share.example.com/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60"}"#
            : #"{"error": "title not supported"}"#
        guard let http = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct ShareLinkRequestTests {
    private let apiClient: APIClient
    private let share = ShareLinkRequest()
    private let link = URL(string: "https://share.example.com/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60")!

    init() {
        ShareProtocol.status = 201
        ShareProtocol.requests = []
        ShareProtocol.body = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ShareProtocol.self]
        apiClient = Biinge.APIClient(baseURL: URL(string: "https://api.example.com/api/v1")!, authManager: AuthManager(), configuration: configuration)
    }

    @Test(arguments: zip([DetailKind.movie, .series, .game], ["movie", "tv", "game"]))
    func aShareSendsTheTitlesTypeAndIDAndIsReadyWithTheLink(kind: DetailKind, type: String) async throws {
        await share.start(kind: kind, id: 603, apiClient: apiClient)

        let body = try #require(ShareProtocol.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(ShareProtocol.requests == ["POST /api/v1/shares"])
        #expect(Set(json.keys) == ["type", "object_id"])
        #expect(json["type"] as? String == type)
        #expect(json["object_id"] as? Int == 603)
        #expect(share.phase == .ready(link))
    }

    @Test func aFailedShareShowsTheErrorAndNoLink() async {
        ShareProtocol.status = 422
        await share.start(kind: .movie, id: 603, apiClient: apiClient)

        #expect(share.phase == .failed("title not supported"))
    }

    @Test func anUnknownTitleFails() async {
        ShareProtocol.status = 404
        await share.start(kind: .game, id: 603, apiClient: apiClient)

        #expect(share.phase == .failed(APIError.server(status: 404).localizedDescription))
    }

    @Test func aSecondTapWhileCreatingSendsNoSecondRequest() async {
        let first = Task { await share.start(kind: .movie, id: 603, apiClient: apiClient) }
        let second = Task { await share.start(kind: .movie, id: 603, apiClient: apiClient) }
        await first.value
        await second.value

        #expect(ShareProtocol.requests == ["POST /api/v1/shares"])
        #expect(share.phase == .ready(link))
    }

    @Test func resetAfterTheSheetClosesReturnsToIdleAndATapSharesAgain() async {
        ShareProtocol.status = 422
        await share.start(kind: .movie, id: 603, apiClient: apiClient)
        share.reset()

        #expect(share.phase == .idle)

        ShareProtocol.status = 201
        await share.start(kind: .movie, id: 603, apiClient: apiClient)

        #expect(share.phase == .ready(link))
        #expect(ShareProtocol.requests == ["POST /api/v1/shares", "POST /api/v1/shares"])
    }
}
