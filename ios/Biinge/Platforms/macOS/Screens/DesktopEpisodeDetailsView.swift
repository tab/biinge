import JellyfinAPI
import SwiftUI

/// The Mac episode details sheet: the wide still, the series, season, episode and quality badges, the title and full synopsis, the resume progress, then Play, Resume or Play Again, Watched, the runtime, air date and rating, and the facts
struct DesktopEpisodeDetailsView: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    /// The series' TMDB ID, for the episode's watched mark in the store
    let seriesID: Int
    let seriesTitle: String
    /// The series' creators, which stand in for an episode with no directors
    let creators: [String]?
    let seasonNumber: Int
    let episode: EpisodeSummary
    /// The played share of the episode's Jellyfin resume position, nil for none
    let share: Double?
    /// The tallest the sheet gets, the height of the page under it
    let maxHeight: CGFloat
    /// Writes the episode's watched mark to the given value and returns whether it landed
    let setWatched: (Bool) async -> Bool
    /// The failed mark's message, which this sheet's alert shows (the page's own alert can't show over the sheet)
    @Binding var watchedFailure: String?

    /// The episode's details for its facts, nil until they load and when the load fails, which leaves the facts out
    @State private var details: EpisodeDetails?
    /// The episode's Jellyfin item for its tracks and badges, nil until it loads and when the library holds none
    @State private var item: BaseItemDto?
    /// The content's measured height, which the sheet follows up to the page's, 0 until its first layout
    @State private var contentHeight: CGFloat = 0
    /// The confirmation of the last Watched click, nil when none shows
    @State private var toast: Toast?
    @State private var isMarkHovered = false
    @Environment(SeriesStore.self) private var store
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let isWatched = store.progress(id: seriesID).map { $0.watchedEpisodes.contains(episode.id) } ?? episode.watched
        let ticks = episode.runtime * 600_000_000
        let play = DetailsPlay(jellyfinID: episode.jellyfinID, isConnected: connection.isConnected, isUnreachable: connection.isUnreachable)
        let aired = episode.airDate.flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
        // the facts carry the date once they load; it holds no time, so it formats in UTC to keep its day
        let date = details == nil ? aired?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)) ?? "" : ""
        let meta = [ticks > 0 ? duration(ticks: ticks) : "", date]
        let factsHeight: CGFloat = if case .play = play { 130 } else { 65 }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // the slot stays clear until the still grows in
                PosterImage(title: episode.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: episode.posterPath, size: "w780"),
                            frame: CGSize(width: 720, height: 340), titleFont: .system(size: 14), titlePadding: 12)
                    .environment(\.imageLoadsClear, true)
                    .overlay {
                        LinearGradient(
                            stops: [.init(color: Color.biingeBackground.opacity(0), location: 0.5), .init(color: Color.biingeBackground, location: 1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("\(seriesTitle) · \(seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)") · Episode \(episode.number)")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                        DesktopQualityBadges(badges: DetailFact.badges(item: item, play: play))
                    }
                    Text(episode.title)
                        .font(.system(size: 34, weight: .bold))
                        .tracking(34 * -0.03)
                    Text(episode.overview)
                        .font(.system(size: 17))
                        .lineSpacing(5)
                        .opacity(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                    if let share {
                        HStack(spacing: 14) {
                            Capsule()
                                .fill(Color.biingeText.opacity(0.22))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.biingeText).frame(width: 200 * share)
                                }
                                .frame(width: 200, height: 4)
                            Text("\(duration(ticks: Int(Double(ticks) * (1 - share)))) left")
                                .font(.system(size: 14.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        switch play {
                        case .play(let jellyfinID), .unreachable(let jellyfinID):
                            let label = share != nil ? "Resume" : isWatched ? "Play Again" : "Play"
                            let action: DetailPrimary.Action = play == .unreachable(jellyfinID) ? .unreachable : .play(jellyfinID)
                            PrimaryPill(primary: DetailPrimary(label: label, detail: nil, systemImage: "play.fill", action: action), server: connection.serverName ?? "server") {
                                // the player opens over the window, so the sheet closes first; a fresh item resumes from the position Jellyfin holds now
                                dismiss()
                                attemptPlay {
                                    guard let service = connection.service else { return }
                                    await connection.play(try await service.item(id: jellyfinID))
                                }
                            }
                            .keyboardShortcut(.defaultAction)
                        case .connect, .notOnServer:
                            EmptyView()
                        }
                        Button {
                            let confirmation = Toast(message: "Episode \(episode.number) marked \(isWatched ? "unwatched" : "watched")", systemImage: isWatched ? nil : "checkmark.circle.fill")
                            toast = confirmation
                            Task {
                                // the alert says nothing changed, so its confirmation goes unless a later click replaced it
                                if await !setWatched(!isWatched), toast == confirmation { toast = nil }
                            }
                        } label: {
                            Label {
                                Text(isWatched ? "Mark Unwatched" : "Mark Watched")
                            } icon: {
                                Image(systemName: isWatched ? "checkmark.circle.badge.xmark" : "checkmark").iconPop(isWatched)
                            }
                                .font(.system(size: 17, weight: .semibold))
                                .padding(.leading, 18)
                                .padding(.trailing, 22)
                                .frame(height: 48)
                                .background(Color.biingeText.opacity(isMarkHovered ? 0.22 : 0.14), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        .onHover { isMarkHovered = $0 }
                        Spacer(minLength: 0)
                        HStack(spacing: 16) {
                            Text(meta.filter { !$0.isEmpty }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                            if let rating = episode.rating, rating > 0 {
                                HStack(spacing: 5) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(Color.biingePrimary)
                                    Text(rating, format: .number.precision(.fractionLength(1)))
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .font(.system(size: 14.5))
                    }
                    .padding(.top, 6)
                    if let note = PlayNote(play: play, server: connection.serverName) {
                        switch note.kind {
                        case .connect:
                            // clearing Not Now brings back the connect screen
                            DesktopDetailNote(systemImage: note.systemImage, text: note.text, link: "Connect Jellyfin") {
                                dismiss()
                                connection.skippedConnect = false
                            }
                        case .unreachable:
                            DesktopDetailNote(systemImage: note.systemImage, color: Color.biingeError, text: note.text, link: "Retry") {
                                Task { await connection.checkReachability() }
                            }
                        case .notOnServer, .playedUnwatched, .seasonNotOnServer, .airs:
                            DesktopDetailNote(systemImage: note.systemImage, text: note.text)
                        }
                    }
                    // the slot holds the block's room (two rows with tracks, one without), as the sheet can't animate its height when the facts land
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(height: factsHeight)
                        if let details {
                            // two columns in the sheet, as on the iPhone, so the credit and date sit above the tracks
                            DesktopDetailFacts(facts: DetailFact.episode(details, creators: creators, item: item, play: play), minimumColumn: 300)
                                .entrance()
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.top, 4)
                .padding(.horizontal, 32)
                .padding(.bottom, 30)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // AppKit lets a sheet run off the screen and never scrolls it, so the sheet stops at the page's height and its content scrolls
        .frame(width: 720, height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
        // pinned to the sheet, so Close stays in reach as the still scrolls away
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
            .padding(16)
        }
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .toast($toast)
        .alert("Couldn’t change Watched", isPresented: Binding(get: { watchedFailure != nil }, set: { if !$0 { watchedFailure = nil } })) {
            Button("OK") {}
        } message: {
            Text(watchedFailure ?? "")
        }
        .task { details = try? await apiClient.episodeDetails(seriesId: seriesID, season: seasonNumber, episode: episode.number) }
        .task(id: "\(episode.jellyfinID ?? "")-\(connection.isConnected)") { await loadItem() }
    }

    /// Loads the episode's Jellyfin item for its tracks and badges (cleared while disconnected); a revoked token disconnects, and any other failure leaves them out
    private func loadItem() async {
        guard let jellyfinID = episode.jellyfinID, let service = connection.service else {
            item = nil
            return
        }
        do {
            item = try await service.item(id: jellyfinID)
        } catch {
            guard !Task.isCancelled else { return }
            _ = await connection.handleFailure(error)
        }
    }
}
