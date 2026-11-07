import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-bleed brand artwork (login and splash) with a darkening bottom gradient
struct BrandBackground: View {
    /// The artwork, shown from the asset catalog at once (UIKit then swaps in a copy decoded off the main thread)
    @State private var image = Image("LoginBackground")

    var body: some View {
        ZStack {
            Color.black
            image
                .resizable()
                .scaledToFill()
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.55), .black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .task {
            #if canImport(UIKit)
            // pre-decode the full-screen PNG off the main thread to avoid a first-render hitch
            if let decoded = await UIImage(named: "LoginBackground")?.byPreparingForDisplay() {
                image = Image(uiImage: decoded)
            }
            #endif
        }
    }
}
