import SwiftUI

extension View {
    /// Adds the Up Next entry point to a library screen's toolbar
    func upNextToolbar() -> some View {
        modifier(UpNextToolbarModifier())
    }
}

/// The queue is reached from every library screen rather than owned by one, since it spans movies and shows alike
private struct UpNextToolbarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["DEBUG_UP_NEXT"] == "1" {
                    isPresented = true
                }
                #endif
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = true
                    } label: {
                        Image(systemName: "play.square.stack")
                    }
                    .accessibilityLabel("Up Next")
                }
            }
            .sheet(isPresented: $isPresented) {
                UpNextView()
                    .preferredColorScheme(colorScheme)
                    .presentationDragIndicator(.hidden)
                    .presentsDetails()
            }
    }
}
