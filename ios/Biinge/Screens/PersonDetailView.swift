import SwiftUI

struct PersonDetailView: View {
    let personId: Int
    @Environment(\.apiClient) private var apiClient

    @State private var details: PersonDetails?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if let details {
                content(details)
            } else if isLoading {
                ProgressView().tint(Color.biingePrimary)
                    .frame(maxWidth: .infinity).padding(.top, 100)
            } else {
                DetailLoadError()
            }
        }
        .background(Color.biingeBackground)
        .navigationTitle(details?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func content(_ person: PersonDetails) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                ProfileCircle(path: person.profilePath, size: 140)
                Text(person.name).font(.biingeTitle2).foregroundStyle(.primary)
                if let birthday = person.birthday, !birthday.isEmpty {
                    Text(birthday).font(.biingeFootnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            if !person.movieCredits.isEmpty {
                DetailSection(title: "Known For") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(person.movieCredits) { credit in
                                NavigationLink(value: DetailRoute.movie(id: credit.id)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        PosterImage(path: credit.posterPath, title: credit.title, size: "w185")
                                            .frame(width: 110)
                                        Text(credit.title)
                                            .font(.biingeCaption2)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .frame(width: 110, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.bottom, 40)
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        details = try? await apiClient.personDetails(id: personId)
        isLoading = false
    }
}
