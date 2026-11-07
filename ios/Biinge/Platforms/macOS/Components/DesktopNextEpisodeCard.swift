import SwiftUI

/// The card in an episode's credits: the next episode's still with the countdown ring, its code, title and synopsis, Play Now and Cancel
struct DesktopNextEpisodeCard: View {
    let series: String
    let next: EpisodeNeighbors.Neighbor
    /// Seconds left on the countdown
    let remaining: Int
    let play: () -> Void
    let cancel: () -> Void

    /// The ring's filled share, which runs a second ahead of remaining so the ring fills as each second passes
    @State private var filled = 0.0

    var body: some View {
        GeometryReader { proxy in
            let width = min(560, proxy.size.width * 0.4)
            VStack(alignment: .leading, spacing: 16) {
                if !series.isEmpty {
                    Text("Up Next in \(series)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.7))
                }
                Button(action: play) {
                    PosterImage(title: next.episode.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: next.episode.posterPath, size: "w780"),
                                frame: CGSize(width: width, height: width * 9 / 16), titleFont: .system(size: 14), titlePadding: 12)
                        .overlay {
                            ZStack {
                                Color.black.opacity(0.3)
                                ZStack {
                                    Circle().fill(.black.opacity(0.35))
                                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 4)
                                    Circle()
                                        .inset(by: 2)
                                        .trim(from: 0, to: filled)
                                        .stroke(Color(rgb: 0xF4F4F2), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 36))
                                }
                                .frame(width: 84, height: 84)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
                        .shadow(color: .black.opacity(0.6), radius: 35, y: 30)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Play \(next.episode.title)")
                VStack(alignment: .leading, spacing: 6) {
                    Text(next.episode.runtime > 0
                        ? "S\(next.season) · E\(next.episode.number)  ·  \(next.episode.runtime) min"
                        : "S\(next.season) · E\(next.episode.number)")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.6))
                    Text(next.episode.title)
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-1)
                        .lineLimit(2)
                    if !next.episode.overview.isEmpty {
                        Text(next.episode.overview)
                            .font(.system(size: 16.5))
                            .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.75))
                            .lineLimit(3)
                    }
                }
                HStack(spacing: 12) {
                    Button(action: play) {
                        Label("Play Now", systemImage: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(rgb: 0x101014))
                            .padding(.horizontal, 24)
                            .frame(height: 48)
                            .background(Color(rgb: 0xF4F4F2), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .keyboardShortcut(.defaultAction)
                    Button(action: cancel) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 24)
                            .frame(height: 48)
                            .background(.white.opacity(0.14), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }
                Text("Playing automatically in \(remaining)s")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.5))
            }
            .frame(width: width, alignment: .leading)
            .padding(.trailing, proxy.size.width * 0.06)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
                .allowsHitTesting(false)
        )
        .foregroundStyle(Color(rgb: 0xF4F4F2))
        .environment(\.colorScheme, .dark)
        .onChange(of: remaining, initial: true) {
            withAnimation(.linear(duration: 1)) {
                filled = Double(NextEpisodeCountdown.length - remaining + 1) / Double(NextEpisodeCountdown.length)
            }
        }
    }
}
