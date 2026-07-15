import SwiftUI
import UIKit

/// Full-bleed brand artwork (login and splash) with a darkening bottom gradient
struct BrandBackground: View {
    // seed synchronously from the asset cache so the splash shows the artwork immediately,
    // then upgrade to the off-thread-decoded copy in .task
    @State private var image: UIImage? = UIImage(named: "LoginBackground")

    var body: some View {
        ZStack {
            Color.black

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }

            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.55), .black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .task {
            // pre-decode the full-screen PNG off the main thread to avoid a first-render hitch
            image = await UIImage(named: "LoginBackground")?.byPreparingForDisplay()
        }
    }
}
