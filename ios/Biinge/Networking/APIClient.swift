import Foundation

/// Thread-safe HTTP client for the biinge API. Endpoints are modeled as methods;
/// a single `perform` funnel adds Bearer auth and transparently refreshes the
/// token pair once on a 401 before retrying.
actor APIClient {
    private let baseURL: URL
    private let authManager: AuthManager
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, authManager: AuthManager) {
        self.baseURL = baseURL
        self.authManager = authManager
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Auth endpoints (unauthenticated)

    func login(email: String, password: String) async throws -> TokenPair {
        try await send("POST", "/users/sessions",
                       body: ["email": email, "password": password],
                       authenticated: false)
    }

    func refresh(refreshToken: String) async throws -> TokenPair {
        try await send("POST", "/users/tokens",
                       body: ["refresh_token": refreshToken],
                       authenticated: false)
    }

    // MARK: - Account

    func me() async throws -> User {
        try await get("/accounts/me")
    }

    // MARK: - Generic verbs

    func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        let request = makeRequest("GET", path, query: query, body: nil)
        let data = try await perform(request, authenticated: true, retried: false)
        return try decode(data)
    }

    func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ method: String,
        _ path: String,
        body: Body,
        authenticated: Bool = true
    ) async throws -> Response {
        let request = makeRequest(method, path, query: [], body: try encoder.encode(body))
        let data = try await perform(request, authenticated: authenticated, retried: false)
        return try decode(data)
    }

    func delete(_ path: String) async throws {
        let request = makeRequest("DELETE", path, query: [], body: nil)
        _ = try await perform(request, authenticated: true, retried: false)
    }

    // MARK: - Request plumbing

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], body: Data?) -> URLRequest {
        var components = URLComponents(string: baseURL.absoluteString + path)!
        if !query.isEmpty {
            components.queryItems = query
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ original: URLRequest, authenticated: Bool, retried: Bool) async throws -> Data {
        var request = original
        if authenticated, let token = await authManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401 where authenticated && !retried:
            try await authManager.refreshTokens(using: self)
            return try await perform(original, authenticated: authenticated, retried: true)
        case 401:
            throw APIError.unauthorized
        case 400, 422:
            throw APIError.badRequest(Self.errorMessage(from: data))
        default:
            throw APIError.server(status: http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private static func errorMessage(from data: Data) -> String {
        struct ErrorResponse: Decodable { let error: String }
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return decoded.error
        }
        return "The request could not be completed."
    }
}
