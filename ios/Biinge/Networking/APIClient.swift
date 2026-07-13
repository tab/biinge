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

    func stats() async throws -> AccountStats {
        try await get("/accounts/stats")
    }

    func updateAccount(_ body: UpdateAccountBody) async throws -> User {
        try await send("PATCH", "/accounts/", body: body)
    }

    // MARK: - Search & trending

    func searchMovies(query: String, page: Int = 1) async throws -> Paginated<SearchMovie> {
        try await get("/search/movies", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    func searchSeries(query: String, page: Int = 1) async throws -> Paginated<SearchSeries> {
        try await get("/search/series", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    func searchPeople(query: String, page: Int = 1) async throws -> Paginated<SearchPerson> {
        try await get("/search/people", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    func trendingMovies() async throws -> Paginated<SearchMovie> {
        try await get("/trending/movies")
    }

    func trendingSeries() async throws -> Paginated<SearchSeries> {
        try await get("/trending/series")
    }

    func trendingPeople() async throws -> Paginated<SearchPerson> {
        try await get("/trending/people")
    }

    // MARK: - Library

    func movies(type: String) async throws -> Paginated<LibraryMovie> {
        try await get("/movies", query: [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "per", value: "10000"),
        ])
    }

    func series(type: String) async throws -> Paginated<LibrarySeries> {
        try await get("/series", query: [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "per", value: "10000"),
        ])
    }

    // MARK: - Details (TMDB-backed)

    func movieDetails(id: Int) async throws -> MovieDetails {
        try await get("/movies/\(id)")
    }

    func seriesDetails(id: Int) async throws -> SeriesDetails {
        try await get("/series/\(id)")
    }

    func seasonDetails(showId: Int, season: Int) async throws -> SeasonDetails {
        try await get("/series/\(showId)/season/\(season)")
    }

    func episodeDetails(showId: Int, season: Int, episode: Int) async throws -> EpisodeDetails {
        try await get("/series/\(showId)/season/\(season)/episode/\(episode)")
    }

    func personDetails(id: Int) async throws -> PersonDetails {
        try await get("/people/\(id)")
    }

    // MARK: - Movie mutations

    func createMovie(_ body: CreateMovieBody) async throws -> MovieDetails {
        try await send("POST", "/movies", body: body)
    }

    func updateMovie(id: Int, _ body: UpdateMovieBody) async throws -> MovieDetails {
        try await send("PATCH", "/movies/\(id)", body: body)
    }

    func deleteMovie(id: Int) async throws {
        try await delete("/movies/\(id)")
    }

    // MARK: - Series mutations

    func createSeries(_ body: CreateSeriesBody) async throws -> SeriesDetails {
        try await send("POST", "/series", body: body)
    }

    func updateSeries(id: Int, _ body: UpdateSeriesBody) async throws -> SeriesDetails {
        try await send("PATCH", "/series/\(id)", body: body)
    }

    func deleteSeries(id: Int) async throws {
        try await delete("/series/\(id)")
    }

    // MARK: - Progress

    func progress(showId: Int) async throws -> WatchProgress {
        try await get("/series/\(showId)/progress")
    }

    func markSeason(showId: Int, seasonId: Int, _ body: MarkSeasonBody) async throws -> WatchProgress {
        try await send("POST", "/series/\(showId)/seasons/\(seasonId)/watched", body: body)
    }

    func unmarkSeason(showId: Int, seasonId: Int) async throws -> WatchProgress {
        try await deleteReturning("/series/\(showId)/seasons/\(seasonId)/watched")
    }

    func markEpisode(showId: Int, seasonId: Int, episodeId: Int, _ body: MarkEpisodeBody) async throws -> WatchProgress {
        try await send("POST", "/series/\(showId)/seasons/\(seasonId)/episodes/\(episodeId)/watched", body: body)
    }

    func unmarkEpisode(showId: Int, seasonId: Int, episodeId: Int) async throws -> WatchProgress {
        try await deleteReturning("/series/\(showId)/seasons/\(seasonId)/episodes/\(episodeId)/watched")
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

    func deleteReturning<Response: Decodable & Sendable>(_ path: String) async throws -> Response {
        let request = makeRequest("DELETE", path, query: [], body: nil)
        let data = try await perform(request, authenticated: true, retried: false)
        return try decode(data)
    }

    // MARK: - Request plumbing

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], body: Data?) -> URLRequest {
        var components = URLComponents(string: baseURL.absoluteString + path) ?? URLComponents()
        if !query.isEmpty {
            components.queryItems = query
        }
        var request = URLRequest(url: components.url ?? baseURL)
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
