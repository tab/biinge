import Testing
@testable import Biinge

struct SeriesDetailsCountsTests {
    private func season(number: Int, episodesCount: Int) -> SeasonSummary {
        SeasonSummary(id: number, title: "S\(number)", number: number, posterPath: "/p.jpg", episodesCount: episodesCount, airDate: nil)
    }

    private func series(seasonsCount: Int?, episodesCount: Int?, seasons: [SeasonSummary]) -> SeriesDetails {
        SeriesDetails(
            id: 1, title: "Show", posterPath: "/p.jpg", pinned: false, state: .none,
            overview: "", status: "Ended", releaseDate: nil,
            seasonsCount: seasonsCount, episodesCount: episodesCount, rating: nil,
            credits: [], recommendations: [], videos: [], seasons: seasons
        )
    }

    @Test func regularSeasonsCountPrefersServerValue() {
        let details = series(seasonsCount: 3, episodesCount: nil, seasons: [])

        #expect(details.regularSeasonsCount == 3)
    }

    @Test func regularSeasonsCountFallsBackExcludingSpecials() {
        let details = series(
            seasonsCount: nil, episodesCount: nil,
            seasons: [season(number: 0, episodesCount: 5), season(number: 1, episodesCount: 8), season(number: 2, episodesCount: 8)]
        )

        #expect(details.regularSeasonsCount == 2)
    }

    @Test func totalEpisodesCountPrefersServerValue() {
        let details = series(seasonsCount: nil, episodesCount: 20, seasons: [])

        #expect(details.totalEpisodesCount == 20)
    }

    @Test func totalEpisodesCountFallsBackToSummedSeasons() {
        let details = series(
            seasonsCount: nil, episodesCount: nil,
            seasons: [season(number: 0, episodesCount: 5), season(number: 1, episodesCount: 8)]
        )

        #expect(details.totalEpisodesCount == 13)
    }
}
