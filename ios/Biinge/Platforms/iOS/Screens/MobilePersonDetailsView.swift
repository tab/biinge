import SwiftUI

struct MobilePersonDetailsView: View {
    let personId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(\.presentTitle) private var presentTitle
    @Environment(\.presentSeries) private var presentSeries

    @State private var details: PersonDetails?
    @State private var isLoading = true
    /// Shows the whole biography instead of its first lines
    @State private var isBiographyExpanded = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                if let details {
                    content(details)
                } else if isLoading {
                    ProgressView().tint(Color.biingeLoader)
                        .frame(maxWidth: .infinity).padding(.top, 220)
                } else {
                    DetailLoadError()
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            CloseButton()
        }
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func content(_ person: PersonDetails) -> some View {
        let cast = person.movieCredits.filter { $0.type != "Director" }
        let crew = person.movieCredits.filter { $0.type == "Director" }
        let biography = person.biography ?? ""

        return VStack(spacing: 0) {
            posterHeader(person)

            VStack(alignment: .leading, spacing: 24) {
                if !biography.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(biography)
                            .font(.body)
                            .lineSpacing(3)
                            .foregroundStyle(Color.biingeText.opacity(0.82))
                            .lineLimit(isBiographyExpanded ? nil : 5)
                        // shortcut: 200 characters stands in for five lines of body text, so a shorter biography clips with no More at large Dynamic Type sizes; measure the text if that shows up
                        if biography.count > 200 {
                            Button(isBiographyExpanded ? "Less" : "More") { isBiographyExpanded.toggle() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.biingeText)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if !cast.isEmpty {
                    creditsGrid(title: person.gender == 1 ? "Actress" : "Actor", items: cast)
                }
                if !person.seriesCredits.isEmpty {
                    seriesCreditsGrid(title: "TV Shows", items: person.seriesCredits)
                }
                if !crew.isEmpty {
                    creditsGrid(title: "Director", items: crew)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCardBackground()
        }
        // pinned to the scroll view's width, because a page answering a pixel wider pans sideways
        .containerRelativeFrame(.horizontal, alignment: .leading)
    }

    private func posterHeader(_ person: PersonDetails) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.biingeSecondaryCard)
                .aspectRatio(4.0 / 6.0, contentMode: .fit)
                .overlay {
                    CachedImage(url: Config.tmdbImageURL(path: person.profilePath, size: "w780"), maxPixel: 1200, grayscale: true) {
                        Color.clear
                    }
                }
                .clipped()

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.5), .black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.biingeTitle1)
                    .foregroundStyle(.white)
                if let birthday = person.birthday, !birthday.isEmpty {
                    Text(formatDate(birthday))
                        .font(.biingeHeadline)
                        .foregroundStyle(Color.biingeGray)
                }
            }
            .padding(.leading, 15)
            .padding(.bottom, 40)
        }
    }

    private func creditsGrid(title: String, items: [MovieCredit]) -> some View {
        DetailSection(title: title) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(items) { credit in
                    // a director who also acts has the movie in both grids, so each grid names its own cells
                    let source = "\(title)-\(credit.id)"
                    Button {
                        presentTitle(.movie(credit.id), source)
                    } label: {
                        PosterImage(path: credit.posterPath, title: credit.title, size: "w342", cornerRadius: 10)
                            .trackedBadge(.movie(credit.id))
                    }
                    .buttonStyle(.pressable)
                    .detailTransitionSource(source)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func seriesCreditsGrid(title: String, items: [SeriesCredit]) -> some View {
        DetailSection(title: title) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(items) { credit in
                    Button {
                        presentSeries(credit.id)
                    } label: {
                        PosterImage(path: credit.posterPath, title: credit.title, size: "w342", cornerRadius: 10)
                            .trackedBadge(.series(credit.id))
                    }
                    .buttonStyle(.pressable)
                    .detailTransitionSource("series-\(credit.id)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func formatDate(_ raw: String) -> String {
        guard raw.count >= 10 else { return raw }
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return raw }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        details = try? await apiClient.personDetails(id: personId)
        isLoading = false
    }
}
