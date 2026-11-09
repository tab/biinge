import Foundation

/// Thread-safe HTTP client for the biinge API; refreshes the token pair once on 401
actor APIClient {
    private let baseURL: URL
    /// The session the requests authenticate with (the stores read it to drop a deferred write once its session ends)
    let authManager: AuthManager
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Creates the client (tests pass a configuration with a stub URL protocol)
    init(baseURL: URL, authManager: AuthManager, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        self.authManager = authManager
        // fail fast instead of the 60s default so an unreachable server errors in seconds
        let config = configuration
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
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

    func stats(period: StatsPeriod = .week) async throws -> AccountStats {
        try await get("/accounts/stats", query: [
            URLQueryItem(name: "period", value: period.rawValue),
        ])
    }

    func updateAccount(_ body: UpdateAccountBody) async throws -> User {
        try await send("PATCH", "/accounts/", body: body)
    }

    // MARK: - Jellyfin

    func jellyfinConnection() async throws -> JellyfinConnectionStatus {
        try await get("/accounts/integrations/jellyfin/connection")
    }

    func connectJellyfin(_ body: JellyfinConnectionRequest) async throws -> JellyfinConnectionStatus {
        try await send("PUT", "/accounts/integrations/jellyfin/connection", body: body)
    }

    func disconnectJellyfin() async throws {
        try await delete("/accounts/integrations/jellyfin/connection")
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

    func searchGames(query: String, page: Int = 1) async throws -> Paginated<SearchGame> {
        try await get("/search/games", query: [
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

    func trendingGames() async throws -> Paginated<SearchGame> {
        try await get("/trending/games")
    }

    func trendingPeople() async throws -> Paginated<SearchPerson> {
        try await get("/trending/people")
    }

    // MARK: - Up next

    func upNext() async throws -> UpNext {
        try await get("/up-next")
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

    func games(type: String) async throws -> Paginated<LibraryGame> {
        try await get("/games", query: [
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

    func seasonDetails(seriesId: Int, season: Int) async throws -> SeasonDetails {
        try await get("/series/\(seriesId)/season/\(season)")
    }

    func episodeDetails(seriesId: Int, season: Int, episode: Int) async throws -> EpisodeDetails {
        try await get("/series/\(seriesId)/season/\(season)/episode/\(episode)")
    }

    func gameDetails(id: Int) async throws -> GameDetails {
        try await get("/games/\(id)")
    }

    func personDetails(id: Int) async throws -> PersonDetails {
        try await get("/people/\(id)")
    }

    // MARK: - Shares

    func createShare(_ body: CreateShareBody) async throws -> Share {
        try await send("POST", "/shares", body: body)
    }

    // MARK: - Movie mutations

    func createMovie(_ body: CreateMovieBody) async throws -> MovieDetails {
        try await send("POST", "/movies", body: body)
    }

    func updateMovie(id: Int, _ body: UpdateMovieBody) async throws -> MovieDetails {
        try await send("PATCH", "/movies/\(id)", body: body)
    }

    func deleteMovie(id: Int, session: Int) async throws {
        try await delete("/movies/\(id)", session: session)
    }

    // MARK: - Series mutations

    func createSeries(_ body: CreateSeriesBody) async throws -> SeriesDetails {
        try await send("POST", "/series", body: body)
    }

    func updateSeries(id: Int, _ body: UpdateSeriesBody) async throws -> SeriesDetails {
        try await send("PATCH", "/series/\(id)", body: body)
    }

    func deleteSeries(id: Int, session: Int) async throws {
        try await delete("/series/\(id)", session: session)
    }

    // MARK: - Game mutations

    func createGame(_ body: CreateGameBody) async throws -> GameDetails {
        try await send("POST", "/games", body: body)
    }

    func updateGame(id: Int, _ body: UpdateGameBody) async throws -> GameDetails {
        try await send("PATCH", "/games/\(id)", body: body)
    }

    func deleteGame(id: Int, session: Int) async throws {
        try await delete("/games/\(id)", session: session)
    }

    // MARK: - Progress

    func progress(seriesId: Int) async throws -> WatchProgress {
        try await get("/series/\(seriesId)/progress")
    }

    func markSeries(seriesId: Int, _ body: MarkSeriesBody) async throws -> WatchProgress {
        try await send("POST", "/series/\(seriesId)/watched", body: body)
    }

    func markSeason(seriesId: Int, seasonId: Int, _ body: MarkSeasonBody) async throws -> WatchProgress {
        try await send("POST", "/series/\(seriesId)/seasons/\(seasonId)/watched", body: body)
    }

    func unmarkSeason(seriesId: Int, seasonId: Int) async throws -> WatchProgress {
        try await deleteReturning("/series/\(seriesId)/seasons/\(seasonId)/watched")
    }

    func markEpisode(seriesId: Int, seasonId: Int, episodeId: Int, _ body: MarkEpisodeBody) async throws -> WatchProgress {
        try await send("POST", "/series/\(seriesId)/seasons/\(seasonId)/episodes/\(episodeId)/watched", body: body)
    }

    func unmarkEpisode(seriesId: Int, seasonId: Int, episodeId: Int) async throws -> WatchProgress {
        try await deleteReturning("/series/\(seriesId)/seasons/\(seasonId)/episodes/\(episodeId)/watched")
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

    /// Sends a DELETE, bound to `session` when one is given (a value of `AuthManager.sessionsEnded`)
    func delete(_ path: String, session: Int? = nil) async throws {
        let request = makeRequest("DELETE", path, query: [], body: nil)
        _ = try await perform(request, authenticated: true, retried: false, authSession: session)
    }

    func deleteReturning<Response: Decodable & Sendable>(_ path: String) async throws -> Response {
        let request = makeRequest("DELETE", path, query: [], body: nil)
        let data = try await perform(request, authenticated: true, retried: false)
        return try decode(data)
    }

    // MARK: - Request plumbing

    /// Client identifier sent on every request, e.g. "Biinge/1.0.0 (build 12; iOS 26.0.0)", naming the platform it runs on
    static let userAgent: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Biinge/\(version) (build \(build); \(DeviceInfo.osName) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion))"
    }()

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], body: Data?) -> URLRequest {
        var components = URLComponents(string: baseURL.absoluteString + path) ?? URLComponents()
        if !query.isEmpty {
            components.queryItems = query
        }
        var request = URLRequest(url: components.url ?? baseURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Sends the request, refreshing the tokens and retrying once on 401 (a request bound to `authSession` throws unauthorized instead of sending or retrying once that session has ended)
    private func perform(_ original: URLRequest, authenticated: Bool, retried: Bool, authSession: Int? = nil) async throws -> Data {
        var request = original
        if authenticated {
            // one hop reads both, so the token always belongs to the session checked
            let (token, current) = await MainActor.run { [authManager] in (authManager.accessToken, authManager.sessionsEnded) }
            if let authSession, authSession != current { throw APIError.unauthorized }
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
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
            // the next account's tokens never refresh for a bound request, and the retry checks the session again after the refresh
            if let authSession, await authManager.sessionsEnded != authSession { throw APIError.unauthorized }
            try await authManager.refreshTokens(using: self)
            return try await perform(original, authenticated: authenticated, retried: true, authSession: authSession)
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
            // a decode failure means the response shape diverged from the model;
            // the server-side Sentry can't see this, so report it from the client
            Monitoring.capture(error, operation: "decode \(T.self)")
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
