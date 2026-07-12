import SwiftUI

struct PersonDetailView: View {
    let personId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(\.presentMovie) private var presentMovie
    @Environment(\.dismiss) private var dismiss

    @State private var details: PersonDetails?
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                if let details {
                    content(details)
                } else if isLoading {
                    ProgressView().tint(Color.biingePrimary)
                        .frame(maxWidth: .infinity).padding(.top, 220)
                } else {
                    DetailLoadError()
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            closeButton
        }
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func content(_ person: PersonDetails) -> some View {
        let cast = person.movieCredits.filter { $0.type != "Director" }
        let crew = person.movieCredits.filter { $0.type == "Director" }

        return VStack(spacing: 0) {
            posterHeader(person)

            VStack(alignment: .leading, spacing: 24) {
                if !cast.isEmpty {
                    creditsGrid(title: person.gender == 1 ? "Actress" : "Actor", items: cast)
                }
                if !crew.isEmpty {
                    creditsGrid(title: "Director", items: crew)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.biingeCard)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
        }
    }

    private func posterHeader(_ person: PersonDetails) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.biingeSecondaryCard)
                .aspectRatio(4.0 / 6.0, contentMode: .fit)
                .overlay {
                    if let url = Config.tmdbImageURL(path: person.profilePath, size: "w780") {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill().grayscale(1)
                        } placeholder: {
                            Color.clear
                        }
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
                    .font(.system(size: 26, weight: .bold))
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.biingeSubhead)
                .foregroundStyle(Color.biingeGrayDark)
                .padding(.horizontal, 10)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3),
                spacing: 5
            ) {
                ForEach(items) { credit in
                    Button {
                        presentMovie(credit.id)
                    } label: {
                        PosterImage(path: credit.posterPath, title: credit.title, size: "w342", cornerRadius: 6)
                            .overlay(alignment: .topLeading) {
                                if let state = credit.state, state != .none {
                                    checkBadge
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 5)
        }
    }

    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(6)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.5), in: Circle())
        }
        .padding(.leading, 16)
        .padding(.top, 16)
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
