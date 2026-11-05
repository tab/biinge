import SwiftUI

/// Runs a Play's lookups and start, and shows the shell's error with the reason and Try Again when they throw
struct AttemptPlayAction: Equatable {
    let perform: @MainActor (_ attempt: @escaping @MainActor () async throws -> Void) -> Void

    @MainActor func callAsFunction(_ attempt: @escaping @MainActor () async throws -> Void) {
        perform(attempt)
    }

    // the writer's closure reads its state when it runs, so every action it makes does the same thing
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// Runs a Play's lookups and start, and shows the shell's error with the reason and Try Again when they throw
    @Entry var attemptPlay = AttemptPlayAction { _ in }
}

extension View {
    /// Gives the screens below attemptPlay and shows its failures in an alert with Try Again (a revoked token disconnects instead)
    func playFailureAlert(connection: JellyfinConnection) -> some View {
        modifier(PlayFailureAlert(connection: connection))
    }
}

/// Holds the failed Play the alert shows
private struct PlayFailureAlert: ViewModifier {
    let connection: JellyfinConnection

    /// The failure's reason and the Play Try Again runs again, nil when no alert shows
    @State private var failure: (message: String, attempt: @MainActor () async throws -> Void)?

    func body(content: Content) -> some View {
        content
            .environment(\.attemptPlay, AttemptPlayAction { attempt in run(attempt) })
            .alert("Can’t play", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }), presenting: failure) { failure in
                Button("Try Again") { run(failure.attempt) }
                Button("Cancel", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
    }

    /// Runs the Play, keeping it for Try Again when it fails
    private func run(_ attempt: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await attempt()
            } catch {
                if await connection.handleFailure(error) { return }
                failure = (error.localizedDescription, attempt)
            }
        }
    }
}
