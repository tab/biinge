import SwiftUI

/// A person's page from biinge: the portrait, birthday, name and biography, then the movie and TV credits as poster grids that open their details
struct DesktopPersonDetailsView: View {
    let apiClient: APIClient
    /// The person's TMDB ID
    let id: Int

    @State private var details: PersonDetails?
    /// The load's error message, nil once the page is on screen
    @State private var failure: String?
    /// Shows the whole biography instead of its first lines
    @State private var isBiographyExpanded = false

    /// A movie or TV credit as the grids show it (the role is the character played or the crew job, nil for TV)
    private struct Credit {
        let details: DetailsTitle
        let title: String
        let role: String?
        let posterPath: String
    }

    var body: some View {
        Group {
            if let details {
                page(details)
            } else if let failure {
                ContentUnavailableView {
                    Label("Can’t reach Biinge", systemImage: "icloud.slash")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Retry") {
                        self.failure = nil
                        Task { await load() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .navigationTitle(details?.name ?? "")
        .task { await load() }
    }

    private func page(_ person: PersonDetails) -> some View {
        let initials = person.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        let birthday = person.birthday ?? ""
        // TMDB sends the birthday as yyyy-MM-dd, a calendar date, so it's shown in GMT to keep the day
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = .gmt
        let born = (try? Date(birthday, strategy: .iso8601.year().month().day())).map { "Born \($0.formatted(style))" } ?? birthday
        let biography = person.biography ?? ""
        let movies = person.movieCredits.map { Credit(details: .movie($0.id), title: $0.title, role: $0.type, posterPath: $0.posterPath) }
        let series = person.seriesCredits.map { Credit(details: .series($0.id), title: $0.title, role: nil, posterPath: $0.posterPath) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                // the portrait stays level with the Born line however long the biography runs
                HStack(alignment: .top, spacing: 40) {
                    // greyscale, as the iPhone's person page
                    CachedImage(url: Config.tmdbImageURL(path: person.profilePath, size: "w500"), maxPixel: 400, grayscale: true) {
                        ZStack {
                            Color.biingeSecondaryCard
                            Text(initials)
                                .font(.system(size: 64, weight: .semibold))
                                .foregroundStyle(Color.biingeGrayDark)
                        }
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
                    .shadow(color: Color.biingeShadow.opacity(0.4), radius: 30, y: 24)
                    VStack(alignment: .leading, spacing: 12) {
                        if !born.isEmpty {
                            Text(born)
                                .font(.system(size: 15, weight: .semibold))
                                .opacity(0.72)
                        }
                        Text(person.name)
                            .font(.system(size: 64, weight: .bold))
                            .tracking(64 * -0.035)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                        if !biography.isEmpty {
                            Text(biography)
                                .font(.system(size: 18))
                                .lineSpacing(5)
                                .opacity(0.82)
                                .lineLimit(isBiographyExpanded ? nil : 5)
                            // shortcut: 400 characters stands in for five lines at the column's width, measure the text if short bios still show the button
                            if biography.count > 400 {
                                Button(isBiographyExpanded ? "Less" : "More") { isBiographyExpanded.toggle() }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                }
                if movies.isEmpty && series.isEmpty {
                    ContentUnavailableView(
                        "No credits yet",
                        systemImage: "film",
                        description: Text("The Biinge catalog has no movies or shows for \(person.name).")
                    )
                    .padding(.vertical, 60)
                }
                grid("Movies", credits: movies)
                grid("TV Shows", credits: series)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 80)
        }
    }

    /// A titled grid of credit posters with their roles that open their details, left out when it has no credits
    @ViewBuilder
    private func grid(_ title: String, credits: [Credit]) -> some View {
        if !credits.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                    Text("\(credits.count)")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 22)], alignment: .leading, spacing: 30) {
                    // a person can hold two credits on one title, so the position is the identity
                    ForEach(credits.indices, id: \.self) { index in
                        let credit = credits[index]
                        NavigationLink(value: DesktopRoute.title(credit.details)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Color.clear
                                    .aspectRatio(2 / 3, contentMode: .fit)
                                    .overlay {
                                        GeometryReader { proxy in
                                            PosterImage(title: credit.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: credit.posterPath, size: "w342"),
                                                        frame: proxy.size, titleFont: .system(size: 14), titlePadding: 12)
                                        }
                                    }
                                    .trackedBadge(credit.details)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.biingeText.opacity(0.07), lineWidth: 1))
                                    .posterHover(cornerRadius: 10)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(credit.title)
                                        .font(.system(size: 15, weight: .semibold))
                                    if let role = credit.role, !role.isEmpty {
                                        Text(role)
                                            .font(.system(size: 13.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Loads the person from biinge; a failure shows the offline state
    private func load() async {
        do {
            details = try await apiClient.personDetails(id: id)
            failure = nil
        } catch {
            // leaving the screen cancels the load, which is no failure
            guard !Task.isCancelled else { return }
            if details == nil { failure = error.localizedDescription }
        }
    }
}
