import SwiftUI

/// The user's ready-to-watch queue: aired episodes and released movies from the shows and films they've pinned
struct UpNextView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.presentSeries) private var presentSeries
    @Environment(\.presentMovie) private var presentMovie

    @State private var upNext: UpNext?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Up Next")
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && upNext == nil {
            ProgressView().tint(Color.biingeLoader)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let upNext, !upNext.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !upNext.episodes.isEmpty {
                        section("New Episodes") {
                            ForEach(upNext.episodes) { episode in
                                Button {
                                    presentSeries(episode.seriesId)
                                } label: {
                                    UpNextRow(
                                        posterPath: episode.seriesPosterPath,
                                        title: episode.seriesTitle,
                                        detail: episodeLabel(episode),
                                        date: UpNextDate.format(episode.airDate)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !upNext.movies.isEmpty {
                        section("Movies") {
                            ForEach(upNext.movies) { movie in
                                Button {
                                    presentMovie(movie.id)
                                } label: {
                                    UpNextRow(
                                        posterPath: movie.posterPath,
                                        title: movie.title,
                                        detail: ratingText(movie.rating),
                                        date: UpNextDate.format(movie.releaseDate)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .refreshable { await load() }
        } else if failed {
            ContentUnavailableView {
                Label("Couldn't load Up Next", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Nothing on deck",
                systemImage: "calendar",
                description: Text("Pin a show you're watching or a movie you want, and its next episode or release shows up here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.biingeSubhead)
                .foregroundStyle(Color.biingeText)

            content()
        }
    }

    private func episodeLabel(_ episode: UpNextEpisode) -> String {
        let code = "S\(episode.seasonNumber) · E\(episode.number)"
        return episode.title.isEmpty ? code : "\(code) · \(episode.title)"
    }

    private func ratingText(_ rating: Double?) -> String {
        guard let rating, rating > 0 else { return "" }
        return String(format: "★ %.1f", rating)
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            upNext = try await apiClient.upNext()
            failed = false
        } catch {
            failed = true
        }
    }
}

/// A shared Up Next row so shows and movies look identical: poster, title, a detail line, and a date
private struct UpNextRow: View {
    let posterPath: String
    let title: String
    let detail: String
    let date: String

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: posterPath, title: title, size: "w185", cornerRadius: 10)
                .frame(width: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.biingeHeadline)
                    .foregroundStyle(Color.biingeText)
                    .lineLimit(1)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.biingeFootnote)
                        .foregroundStyle(Color.biingeTextSecondary)
                        .lineLimit(2)
                }

                if !date.isEmpty {
                    Text(date)
                        .font(.biingeCaption2)
                        .foregroundStyle(Color.biingeGraniteGray)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

/// Formats a TMDB `yyyy-MM-dd` date string for display, falling back to the raw value
private enum UpNextDate {
    static func format(_ raw: String) -> String {
        guard let date = isoParser.date(from: raw) else { return raw }
        return displayFormatter.string(from: date)
    }

    private static let isoParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
