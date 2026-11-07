import Foundation
import Observation

/// The Jellyfin connect flow on every platform: finding the server, the sign-in form, connecting with Cancel, and the server errors
@MainActor
@Observable
final class ConnectFlow {
    enum Step: Equatable {
        /// Reads the server address from the API and the server's name from Jellyfin
        case checking
        case signIn
        /// Both sign-ins run until the screen gives way to the connection, or Cancel returns to the form
        case connecting
        /// The server check failed with this message
        case unreachable(String)
        /// This biinge instance has no Jellyfin server
        case noServer
    }

    private let connection: JellyfinConnection
    private let apiClient: APIClient

    /// The step on screen (Try Again goes back to Checking, which the screen runs the check for)
    var step = Step.checking
    /// The server address the API reports
    private(set) var server = ""
    /// The name the server reports, shown on the form
    private(set) var serverName = ""
    var user: String
    var password = ""
    /// The failed sign-in's message (an edit to either field clears it)
    var errorMessage: String?
    /// Counts sign-in attempts, so one that Cancel dropped can't change the screen when it ends
    private var attempt = 0

    /// A flow on Checking, with the user Reconnect kept on the form
    init(connection: JellyfinConnection, apiClient: APIClient) {
        self.connection = connection
        self.apiClient = apiClient
        var user = connection.reconnectPrefill ?? ""
        #if DEBUG
        // JELLYFIN_USER and JELLYFIN_PASSWORD fill the form in Debug launches, after Reconnect's user
        let env = ProcessInfo.processInfo.environment
        if user.isEmpty { user = env["JELLYFIN_USER"] ?? "" }
        password = env["JELLYFIN_PASSWORD"] ?? ""
        #endif
        self.user = user
    }

    /// Checks the server the API names, then shows the form, the missing server or the unreachable one
    func check() async {
        do {
            let found = try await connection.checkServer(apiClient: apiClient)
            // the screen went away during the check
            guard !Task.isCancelled else { return }
            server = found.address
            serverName = found.name
            errorMessage = nil
            step = .signIn
            #if DEBUG
            // JELLYFIN_AUTOCONNECT signs in once the form shows, in its own Task as leaving Checking cancels this one
            if ProcessInfo.processInfo.environment["JELLYFIN_AUTOCONNECT"] != nil {
                Task { await connect() }
            }
            #endif
        } catch JellyfinConnectionError.noServer {
            step = .noServer
        } catch {
            guard !Task.isCancelled else { return }
            // the error names the server by the address the API reported, and by its name when an earlier check had one
            server = connection.checkedAddress ?? ""
            serverName = connection.serverName ?? URL(string: server)?.host() ?? "the server"
            step = .unreachable(error.localizedDescription)
        }
    }

    /// Signs in to Jellyfin and connects the account, or returns to the form with the error (the connection replaces the screen on success)
    func connect() async {
        // Connecting also stops a second submit while one runs
        guard step == .signIn else { return }
        step = .connecting
        attempt += 1
        let started = attempt
        do {
            try await connection.connect(server: server, user: user, password: password, apiClient: apiClient)
        } catch {
            guard started == attempt else { return }
            // back to the form with the user kept, so a wrong password retries with only the password
            errorMessage = error.localizedDescription
            step = .signIn
        }
    }

    /// Drops the sign-in in flight and returns to the form with the fields kept
    func cancel() {
        connection.cancelConnect()
        attempt += 1
        errorMessage = nil
        step = .signIn
    }
}
