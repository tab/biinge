import Testing
@testable import Biinge

struct WatchProgressTests {
    private func base(
        state: WatchState = .none,
        trackedState: WatchState? = nil,
        seasons: [Int] = [],
        episodes: [Int] = []
    ) -> WatchProgress {
        WatchProgress(id: 1, state: state, trackedState: trackedState, watchedSeasons: seasons, watchedEpisodes: episodes)
    }

    @Test func finishingEverySeasonMarksEndedShowWatched() {
        // the episode total drifts far above the two real episodes; season completeness must still win
        let progress = base().togglingSeason(id: 10, episodeIds: [1, 2], watched: true, totalSeasons: 1, showStatus: "Ended")

        #expect(progress.state == .watched)
        #expect(progress.watchedSeasons == [10])
        #expect(Set(progress.watchedEpisodes) == [1, 2])
    }

    @Test func partialSeasonStaysWatching() {
        let progress = base().togglingEpisode(id: 1, watched: true, seasonId: 10, totalSeasons: 2, showStatus: "Ended")

        #expect(progress.state == .watching)
    }

    @Test func returningSeriesNeverDerivesWatched() {
        let progress = base().togglingSeason(
            id: 10, episodeIds: [1, 2], watched: true, totalSeasons: 1, showStatus: WatchProgress.tvInProductionStatus
        )

        #expect(progress.state == .watching)
    }

    @Test func unmarkingLastEpisodeRevertsToTrackedState() {
        let progress = base(state: .watching, trackedState: .want, episodes: [1])
            .togglingEpisode(id: 1, watched: false, seasonId: 10, totalSeasons: 1, showStatus: "Ended")

        #expect(progress.state == .want)
        #expect(progress.watchedEpisodes.isEmpty)
    }

    @Test func unmarkingLastEpisodeUntracksWhenNothingWasTracked() {
        let progress = base(state: .watching, episodes: [1])
            .togglingEpisode(id: 1, watched: false, seasonId: 10, totalSeasons: 1, showStatus: "Ended")

        #expect(progress.state == .none)
    }

    @Test func togglingSeasonAddsThenRemovesItsEpisodes() {
        let marked = base().togglingSeason(id: 10, episodeIds: [1, 2, 3], watched: true, totalSeasons: 2, showStatus: "Ended")

        #expect(marked.watchedSeasons == [10])
        #expect(Set(marked.watchedEpisodes) == [1, 2, 3])
        #expect(marked.state == .watching)

        let cleared = marked.togglingSeason(id: 10, episodeIds: [1, 2, 3], watched: false, totalSeasons: 2, showStatus: "Ended")

        #expect(cleared.watchedSeasons.isEmpty)
        #expect(cleared.watchedEpisodes.isEmpty)
        #expect(cleared.state == .none)
    }
}
