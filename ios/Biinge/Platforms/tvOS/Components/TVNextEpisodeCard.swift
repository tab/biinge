import SwiftUI

/// The Apple TV card in an episode's credits: Up Next with the seconds left, the next episode's still with the countdown ring, its code, runtime and title, then Play Now (focused) and Cancel
struct TVNextEpisodeCard: View {
    let next: EpisodeNeighbors.Neighbor
    /// Seconds left on the countdown
    let remaining: Int
    let play: () -> Void
    let cancel: () -> Void

    /// The ring's filled share, which runs a second ahead of remaining so the ring fills as each second passes
    @State private var filled = 0.0
    @FocusState private var focusesPlay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Up next · in \(remaining)")
                .textCase(.uppercase)
                .font(.system(size: 24, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.6))
            PosterImage(title: next.episode.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: next.episode.posterPath, size: "w780"),
                        frame: CGSize(width: 520, height: 292.5), titleFont: .system(size: 26), titlePadding: 20)
                .overlay {
                    ZStack {
                        Color.black.opacity(0.3)
                        ZStack {
                            Circle().fill(.black.opacity(0.35))
                            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 5)
                            Circle()
                                .inset(by: 2.5)
                                .trim(from: 0, to: filled)
                                .stroke(Color(rgb: 0xF4F4F2), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "play.fill")
                                .font(.system(size: 44))
                        }
                        .frame(width: 104, height: 104)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 6) {
                Text(next.episode.runtime > 0
                    ? "S\(next.season) · E\(next.episode.number) · \(next.episode.runtime) min"
                    : "S\(next.season) · E\(next.episode.number)")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.65))
                Text(next.episode.title)
                    .font(.system(size: 44, weight: .semibold))
                    .tracking(-0.9)
                    .lineLimit(2)
            }
            HStack(spacing: 22) {
                Button(action: play) {
                    Label("Play Now", systemImage: "play.fill")
                }
                .focused($focusesPlay)
                Button(action: cancel) {
                    Label("Cancel", systemImage: "xmark")
                }
            }
            .buttonStyle(PillButtonStyle())
            .padding(.top, 10)
        }
        .frame(width: 780, alignment: .leading)
        .padding(.trailing, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
        )
        .ignoresSafeArea()
        .foregroundStyle(Color(rgb: 0xF4F4F2))
        // focus sits in the player when the card appears, so the card takes it for Play Now
        .defaultFocus($focusesPlay, true)
        .onAppear { focusesPlay = true }
        .onChange(of: remaining, initial: true) {
            withAnimation(.linear(duration: 1)) {
                filled = Double(NextEpisodeCountdown.length - remaining + 1) / Double(NextEpisodeCountdown.length)
            }
        }
    }
}
