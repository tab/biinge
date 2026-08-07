import SwiftUI

/// The user's ready-to-watch queue: aired episodes, released movies and released games from what they've pinned
struct UpNextView: View {
    @Environment(UpNextStore.self) private var store
    @Environment(\.presentSeries) private var presentSeries
    @Environment(\.presentMovie) private var presentMovie
    @Environment(\.presentGame) private var presentGame

    var body: some View {
        ZStack(alignment: .topLeading) {
            content

            CloseButton()
        }
        .background(Color.biingeBackground)
        // the queue turns over as episodes air and the user watches them, so every open refreshes;
        // the previous queue stays on screen meanwhile
        .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.upNext == nil {
            ProgressView().tint(Color.biingeLoader)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let upNext = store.upNext, !upNext.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    Text("Up Next")
                        .font(.biingeTitle1)
                        .foregroundStyle(.primary)

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

                    if !upNext.games.isEmpty {
                        section("Games") {
                            ForEach(upNext.games) { game in
                                Button {
                                    presentGame(game.id)
                                } label: {
                                    UpNextRow(
                                        posterPath: game.posterPath,
                                        title: game.title,
                                        detail: ratingText(game.rating),
                                        date: UpNextDate.format(game.releaseDate),
                                        source: .igdb
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                // clears the floating close button, the way every other modal seats its title
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .refreshable { await store.load() }
        } else if store.failed {
            ContentUnavailableView {
                Label("Couldn't load Up Next", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await store.load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Nothing on deck",
                systemImage: "calendar",
                description: Text("Pin a show you're watching, or a movie or game you want, and its next episode or release shows up here.")
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
}

/// A shared Up Next row so shows, movies and games look identical: poster, title, a detail line, and a date
private struct UpNextRow: View {
    let posterPath: String
    let title: String
    let detail: String
    let date: String
    var source: PosterImage.Source = .tmdb

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(
                path: posterPath,
                title: title,
                source: source,
                size: source == .igdb ? "cover_big" : "w185",
                cornerRadius: 10
            )
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
