import SwiftUI
import CryptoKit

/// Gravatar avatar derived from the MD5 of the user's email (matching the RN app).
struct Avatar: View {
    let email: String
    var size: CGFloat = 96

    private var url: URL? {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespaces)
        let hash = Insecure.MD5.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?d=mp&s=\(Int(size * 2))")
    }

    var body: some View {
        CachedImage(url: url, maxPixel: size * 3) {
            Circle().fill(Color.biingeSecondaryCard)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
