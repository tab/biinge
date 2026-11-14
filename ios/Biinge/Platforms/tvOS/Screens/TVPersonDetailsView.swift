import SwiftUI

/// Apple TV person page from biinge: the portrait, birthday, name and biography, then Movies and TV Shows rows of credits that open their details
struct TVPersonDetailsView: View {
    let apiClient: APIClient
    /// The person's TMDB ID
    let id: Int

    @State private var details: PersonDetails?
    /// The load's error message, nil once the page is on screen
    @State private var failure: String?
    /// Whether the header (photo, name and biography) holds focus
    @FocusState private var headerFocused: Bool

    var body: some View {
        Group {
            if let details {
                page(details)
            } else if let failure {
                Message(icon: "icloud.slash", title: "Can’t reach Biinge", text: failure, action: "Try Again") {
                    self.failure = nil
                    Task { await load() }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground.ignoresSafeArea())
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 72) {
                VStack(alignment: .leading, spacing: 48) {
                    HStack(spacing: 64) {
                        // black-and-white portrait, as on iPhone (the placeholder is already grey)
                        PosterImage(title: initials, cornerRadius: 0, poster: Config.tmdbImageURL(path: person.profilePath, size: "w500"),
                                    frame: CGSize(width: 300, height: 300), titleFont: .system(size: 26), titlePadding: 20)
                            .grayscale(1)
                            .clipShape(Circle())
                            .shadow(color: Color.biingeShadow.opacity(0.5), radius: 45, y: 40)
                        VStack(alignment: .leading, spacing: 18) {
                            if !born.isEmpty {
                                Text(born)
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(Color.biingeText.opacity(0.7))
                            }
                            Text(person.name)
                                .font(.system(size: 112, weight: .bold))
                                .tracking(112 * -0.035)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                                .foregroundStyle(headerFocused ? Color.biingeTextFocused : Color.biingeText.opacity(0.7))
                        }
                    }
                    if !biography.isEmpty {
                        // the header takes focus as one piece, so the page shows the opening lines rather than a text to scroll
                        Text(biography)
                            .font(.system(size: 30))
                            .lineSpacing(7)
                            .foregroundStyle(headerFocused ? Color.biingeTextFocused : Color.biingeText.opacity(0.75))
                            .lineLimit(5)
                            .frame(maxWidth: 1400, alignment: .leading)
                    }
                }
                .padding(.horizontal, 96)
                // full width and focusable, so up from any credit lands here, scrolls the page back to its top and goes on to the tab bar
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusable()
                .focused($headerFocused)
                // the name and biography brighten while the header holds focus, as a details row's title does
                .animation(MotionCurve.focus.animation(MotionDuration.standard), value: headerFocused)
                if person.movieCredits.isEmpty && person.seriesCredits.isEmpty {
                    VStack(spacing: 18) {
                        Text("No credits yet")
                            .font(.system(size: 40, weight: .semibold))
                        Text("The Biinge catalog has no movies or shows for \(person.name).")
                            .font(.system(size: 29))
                            .foregroundStyle(Color.biingeText.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
                if !person.movieCredits.isEmpty {
                    TVDetailsRow(title: "Movies", count: person.movieCredits.count, spacing: 48, items: person.movieCredits) { credit in
                        NavigationLink(value: TVRoute.title(.movie(credit.id))) {
                            PosterImage(title: credit.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: credit.posterPath, size: "w500"),
                                        frame: CGSize(width: 260, height: 390), titleFont: .system(size: 26), titlePadding: 20)
                                .trackedBadge(.movie(credit.id))
                        }
                        .buttonStyle(TVCardButtonStyle(width: 260, height: 390, cornerRadius: 16, title: credit.title, subtitle: credit.type))
                    }
                }
                if !person.seriesCredits.isEmpty {
                    TVDetailsRow(title: "TV Shows", count: person.seriesCredits.count, spacing: 48, items: person.seriesCredits) { credit in
                        NavigationLink(value: TVRoute.title(.series(credit.id))) {
                            PosterImage(title: credit.title, cornerRadius: 0, poster: Config.tmdbImageURL(path: credit.posterPath, size: "w500"),
                                        frame: CGSize(width: 260, height: 390), titleFont: .system(size: 26), titlePadding: 20)
                                .trackedBadge(.series(credit.id))
                        }
                        .buttonStyle(TVCardButtonStyle(width: 260, height: 390, cornerRadius: 16, title: credit.title, subtitle: nil))
                    }
                }
            }
            .padding(.top, 120)
            .padding(.bottom, 80)
        }
        .ignoresSafeArea()
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
