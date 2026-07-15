import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.biingeBackground.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("biinge")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(Color.biingePrimary)
                ProgressView()
                    .tint(Color.biingeLoader)
            }
        }
    }
}

#Preview {
    SplashView()
}
