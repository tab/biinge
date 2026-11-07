import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

struct DetailFactsTests {
    private let audio = MediaStream(channelLayout: "5.1(side)", displayTitle: "English - Dolby Digital - 5.1", index: 1, isDefault: true, language: "eng", type: .audio)
    private let subtitle = MediaStream(displayTitle: "English - SUBRIP", index: 2, language: "eng", type: .subtitle)
    private let playable = DetailsPlay(jellyfinID: "j1", isConnected: true)

    private func movie(directors: [String]? = ["Michael Mann"], releaseDate: String? = "1995-12-15", status: String? = nil) -> MovieDetails {
        MovieDetails(
            id: 1, title: "Heat", posterPath: "", pinned: false, state: .none, overview: "", status: status, releaseDate: releaseDate,
            runtime: nil, rating: nil, genres: ["Crime"], directors: directors, credits: [], recommendations: [], videos: [], jellyfinID: "j1"
        )
    }

    private func series(creators: [String]? = ["Vince Gilligan"], releaseDate: String? = "2008-01-20", status: String? = nil) -> SeriesDetails {
        SeriesDetails(
            id: 2, title: "Show", posterPath: "", pinned: false, state: .none, overview: "", status: status, releaseDate: releaseDate,
            seasonsCount: 5, episodesCount: nil, rating: nil, genres: [], creators: creators,
            credits: [], recommendations: [], videos: [], seasons: [], jellyfinID: nil
        )
    }

    /// An episode decoded from the API's shape, as it has no memberwise initializer
    private func episode(directors: String = #"["Mike Judge"]"#, airDate: String = "2014-04-06") throws -> EpisodeDetails {
        let json = #"{"id": 5, "title": "Pilot", "number": 1, "posterPath": "", "runtime": 28, "overview": "", "credits": [], "videos": [], "airDate": "\#(airDate)", "directors": \#(directors)}"#
        return try JSONDecoder().decode(EpisodeDetails.self, from: Data(json.utf8))
    }

    /// A game decoded from the API's shape, as it has no memberwise initializer
    private func game(developers: String = #"["Supergiant Games"]"#, releaseDate: String = "2020-09-17", status: String? = nil) throws -> GameDetails {
        let prefix = #"{"id": 6, "title": "Hades", "posterPath": "", "pinned": false, "state": "none", "overview": "", "genres": [], "platforms": []"#
        let statusField = status.map { #", "status": "\#($0)""# } ?? ""
        let json = prefix + #", "releaseDate": "\#(releaseDate)", "developers": \#(developers)"# + statusField + "}"
        return try JSONDecoder().decode(GameDetails.self, from: Data(json.utf8))
    }

    private func item(_ streams: MediaStream...) -> BaseItemDto {
        BaseItemDto(id: "j1", mediaStreams: streams)
    }

    /// The Audio value of an item holding `streams`
    private func audioValue(_ streams: MediaStream...) -> String? {
        DetailFact.movie(movie(), item: BaseItemDto(id: "j1", mediaStreams: streams), play: playable, state: nil).first { $0.label == "Audio" }?.value
    }

    /// The Subtitles fact of an item holding `streams`
    private func subtitlesFact(_ streams: [MediaStream]) -> DetailFact? {
        DetailFact.movie(movie(), item: BaseItemDto(id: "j1", mediaStreams: streams), play: playable, state: nil).first { $0.label == "Subtitles" }
    }

    /// The badges of a playable item holding a video stream of the size, plus `extra`
    private func badges(height: Int? = nil, width: Int? = nil, range: VideoRange? = nil, _ extra: MediaStream...) -> [String] {
        let video = MediaStream(height: height, type: .video, videoRange: range, width: width)
        return DetailFact.badges(item: BaseItemDto(id: "j1", mediaStreams: [video] + extra), play: playable)
    }

    @Test func aMovieShowsItsFactsInOrder() {
        #expect(DetailFact.movie(movie(directors: ["A", "B"], status: "Ended"), item: item(audio, subtitle), play: playable, state: .watched) == [
            DetailFact(label: "Director", value: "A, B"),
            DetailFact(label: "Released", value: "15 Dec 1995"),
            DetailFact(label: "Status", value: "Ended"),
            DetailFact(label: "Audio", value: "English · 5.1"),
            DetailFact(label: "Subtitles", value: "English"),
            DetailFact(label: "List", value: "Watched"),
        ])
    }

    @Test func aMovieHidesWhatItLacksAndKeepsItsStatus() {
        #expect(DetailFact.movie(movie(directors: nil, releaseDate: ""), item: nil, play: playable, state: nil) == [DetailFact(label: "List", value: "Not tracked")])
        #expect(DetailFact.movie(movie(directors: [], releaseDate: nil), item: nil, play: playable, state: .want) == [DetailFact(label: "List", value: "Want to Watch")])
    }

    @Test func anUpcomingFirstAirShowsItsDay() {
        #expect(DetailFact.series(series(releaseDate: "2099-01-05"), state: nil).first { $0.label == "First airs" }?.value == "5 Jan 2099")
    }

    @Test(arguments: [("2026-05-27", "Released"), ("2026-05-28", "Released"), ("2026-05-28T23:59:00.000Z", "Released"), ("2026-05-29", "Releases"), ("2026-12-15", "Releases")])
    func aMovieAndAGameLabelTheirDateByTheDay(date: String, label: String) throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000) // 2026-05-28 20:26 UTC
        let movieFacts = DetailFact.movie(movie(releaseDate: date, status: "Post Production"), item: nil, play: playable, state: nil, now: now)
        let gameFacts = try DetailFact.game(game(releaseDate: date), state: nil, now: now)

        #expect(movieFacts.map(\.label) == ["Director", label, "Status", "List"])
        #expect(gameFacts.map(\.label) == ["Developer", label, "List"])
    }

    @Test(arguments: [("2026-05-27", "First aired"), ("2026-05-28", "First aired"), ("2026-05-29", "First airs"), ("2026-12-15", "First airs")])
    func aSeriesLabelsItsDateByTheDay(date: String, label: String) {
        let now = Date(timeIntervalSince1970: 1_780_000_000) // 2026-05-28 20:26 UTC
        #expect(DetailFact.series(series(releaseDate: date), state: nil, now: now).map(\.label) == ["Created by", label, "List"])
    }

    @Test func aSeriesShowsItsFactsInOrder() {
        #expect(DetailFact.series(series(creators: ["A", "B"], status: "Returning Series"), state: .watching) == [
            DetailFact(label: "Created by", value: "A, B"),
            DetailFact(label: "First aired", value: "2008"),
            DetailFact(label: "Status", value: "Returning"),
            DetailFact(label: "List", value: "Watching"),
        ])
    }

    @Test func aSeriesHidesWhatItLacksAndKeepsItsStatus() {
        #expect(DetailFact.series(series(creators: [], releaseDate: nil), state: nil) == [DetailFact(label: "List", value: "Not tracked")])
    }

    @Test func anEpisodeShowsItsFactsInOrder() throws {
        #expect(try DetailFact.episode(episode(), creators: ["Creator"], item: item(audio, subtitle), play: playable) == [
            DetailFact(label: "Director", value: "Mike Judge"),
            DetailFact(label: "Air date", value: "6 Apr 2014"),
            DetailFact(label: "Audio", value: "English · 5.1"),
            DetailFact(label: "Subtitles", value: "English"),
        ])
    }

    @Test(arguments: ["null", "[]"])
    func anEpisodeWithoutDirectorsShowsTheSeriesCreators(directors: String) throws {
        let facts = try DetailFact.episode(episode(directors: directors), creators: ["A", "B"], item: nil, play: .connect)

        #expect(facts == [DetailFact(label: "Created by", value: "A, B"), DetailFact(label: "Air date", value: "6 Apr 2014")])
    }

    @Test func anEpisodeWithoutDirectorsOrCreatorsHidesTheFact() throws {
        #expect(try DetailFact.episode(episode(directors: "[]", airDate: ""), creators: nil, item: nil, play: .connect).isEmpty)
    }

    @Test func aGameShowsItsFactsInOrder() throws {
        #expect(try DetailFact.game(game(developers: #"["A", "B"]"#, status: "Early Access"), state: .playing) == [
            DetailFact(label: "Developer", value: "A, B"),
            DetailFact(label: "Released", value: "17 Sep 2020"),
            DetailFact(label: "Status", value: "Early Access"),
            DetailFact(label: "List", value: "Playing"),
        ])
    }

    @Test func aGameHidesWhatItLacksAndKeepsItsStatus() throws {
        #expect(try DetailFact.game(game(developers: "[]", releaseDate: "soon"), state: nil) == [DetailFact(label: "List", value: "Not tracked")])
    }

    @Test(arguments: [(WatchState.want, "Want to Play"), (.playing, "Playing"), (.played, "Played")])
    func aGameNamesItsOwnLists(state: WatchState, name: String) throws {
        #expect(try DetailFact.game(game(), state: state).last == DetailFact(label: "List", value: name))
    }

    @Test(arguments: [(WatchState.want, "Want to Watch"), (.watching, "Watching"), (.watched, "Watched")])
    func aSeriesNamesItsLists(state: WatchState, name: String) {
        #expect(DetailFact.series(series(), state: state).last == DetailFact(label: "List", value: name))
    }

    @Test(arguments: [("Canceled", "Cancelled"), ("Returning Series", "Returning"), ("Post Production", "Post-production"), ("In Production", "In production"), ("Ended", "Ended")])
    func aMovieAndASeriesShowTheirStatus(sent: String, shown: String) {
        let expected = DetailFact(label: "Status", value: shown)

        #expect(DetailFact.movie(movie(status: sent), item: nil, play: playable, state: nil).contains(expected))
        #expect(DetailFact.series(series(status: sent), state: nil).contains(expected))
    }

    @Test(arguments: [("Canceled", "Cancelled"), ("Cancelled", "Cancelled"), ("Upcoming", "Upcoming"), ("Early Access", "Early Access")])
    func aGameShowsItsStatus(sent: String, shown: String) throws {
        #expect(try DetailFact.game(game(status: sent), state: nil).contains(DetailFact(label: "Status", value: shown)))
    }

    @Test(arguments: [nil, "", "Released"] as [String?])
    func aMovieAndAGameHideAnAbsentOrReleasedStatus(sent: String?) throws {
        #expect(!DetailFact.movie(movie(status: sent), item: nil, play: playable, state: nil).contains { $0.label == "Status" })
        #expect(try !DetailFact.game(game(status: sent), state: nil).contains { $0.label == "Status" })
    }

    @Test(arguments: [
        ("Released", "2099-01-01", true), ("Early Access", "2099-01-01", true), ("Delisted", "", true),
        ("Upcoming", "2020-01-01", false), ("Cancelled", "2020-01-01", false),
        // no status, or one that says nothing about release, leaves the date to decide
        (nil, "2020-01-01", true), ("", "2020-01-01", true), ("Beta", "2020-01-01", true),
        (nil, "2099-01-01", false), ("", "", false), ("Rumored", "", false),
    ] as [(String?, String, Bool)])
    func aGameIsReleasedByItsStatusThenItsDate(status: String?, releaseDate: String, isReleased: Bool) throws {
        #expect(try game(releaseDate: releaseDate, status: status).isReleased() == isReleased)
    }

    @Test func aGameOutTodayIsReleasedInTheLocalDay() throws {
        // late in the evening behind UTC, where the UTC day is already the 29th (the scheme's test action sets the zone)
        let evening = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 23, minute: 30)))

        #expect(try game(releaseDate: "2026-05-28", status: "").isReleased(now: evening))
        #expect(try !game(releaseDate: "2026-05-29", status: "").isReleased(now: evening))
    }

    @Test func theNotOutNoteNamesTheDateOrItsLack() throws {
        // midnight UTC formatted in UTC is the expected day in any locale, and in a zone behind UTC a local format would say the 14th
        let day = try Date("2099-12-15T00:00:00Z", strategy: .iso8601)
        let shown = day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))

        #expect(try game(releaseDate: "2099-12-15", status: "Upcoming").releaseNote(state: nil) == "Not out yet. Out \(shown).")
        #expect(try game(releaseDate: "", status: "").releaseNote(state: .want) == "Not out yet. No release date.")
    }

    @Test(arguments: [WatchState.playing, .played])
    func aGameTrackedAsPlayingOrPlayedShowsNoNote(state: WatchState) throws {
        #expect(try game(releaseDate: "", status: "").releaseNote(state: state) == nil)
    }

    @Test func aCancelledGameOrAReleasedOneShowsNoNote() throws {
        #expect(try game(releaseDate: "", status: "Cancelled").releaseNote(state: nil) == nil)
        #expect(try game(releaseDate: "2020-01-01", status: "Released").releaseNote(state: nil) == nil)
    }

    @Test func theStatusSitsBetweenTheDatesAndTheList() throws {
        #expect(DetailFact.series(series(status: "Ended"), state: nil).map(\.label) == ["Created by", "First aired", "Status", "List"])
        #expect(try DetailFact.game(game(status: "Ended"), state: nil).map(\.label) == ["Developer", "Released", "Status", "List"])
    }

    @Test(arguments: [DetailsPlay.connect, .notOnServer, .unreachable("j1")])
    func tracksAndBadgesHideUnlessTheTitleCanPlay(play: DetailsPlay) throws {
        let video = MediaStream(height: 2160, type: .video)
        let loaded = item(audio, subtitle, video)

        #expect(DetailFact.movie(movie(), item: loaded, play: play, state: nil).map(\.label) == ["Director", "Released", "List"])
        #expect(try DetailFact.episode(episode(), creators: nil, item: loaded, play: play).map(\.label) == ["Director", "Air date"])
        #expect(DetailFact.badges(item: loaded, play: play).isEmpty)
    }

    @Test func tracksHideWithoutAnItem() {
        #expect(DetailFact.movie(movie(), item: nil, play: playable, state: nil).map(\.label) == ["Director", "Released", "List"])
        #expect(DetailFact.badges(item: nil, play: playable).isEmpty)
    }

    @Test func anItemOfAnotherTitleShowsNoTracksOrBadges() throws {
        let other = BaseItemDto(id: "j2", mediaStreams: [audio, subtitle, MediaStream(height: 2160, type: .video)])

        #expect(DetailFact.movie(movie(), item: other, play: playable, state: nil).map(\.label) == ["Director", "Released", "List"])
        #expect(try DetailFact.episode(episode(), creators: nil, item: other, play: playable).map(\.label) == ["Director", "Air date"])
        #expect(DetailFact.badges(item: other, play: playable).isEmpty)
    }

    @Test func theStreamsComeFromTheMediaSourceWhenTheItemHasNone() {
        let item = BaseItemDto(id: "j1", mediaSources: [MediaSourceInfo(mediaStreams: [audio])])

        #expect(DetailFact.movie(movie(), item: item, play: playable, state: nil).map(\.label) == ["Director", "Released", "Audio", "List"])
    }

    @Test func anItemWithoutStreamsShowsNoTracksOrBadges() {
        let item = BaseItemDto(id: "j1")

        #expect(DetailFact.movie(movie(), item: item, play: playable, state: nil).map(\.label) == ["Director", "Released", "List"])
        #expect(DetailFact.badges(item: item, play: playable).isEmpty)
    }

    @Test func factsWithTheSameValueKeepTheirOwnIDs() {
        let facts = DetailFact.series(series(creators: ["Watching"]), state: .watching)

        #expect(facts.map(\.id) == ["Created by", "First aired", "List"])
    }

    @Test func aReleaseDateThatDoesNotParseIsHidden() {
        #expect(DetailFact.movie(movie(releaseDate: "soon"), item: nil, play: playable, state: nil).map(\.label) == ["Director", "List"])
    }

    @Test func aDateKeepsItsDayInANegativeTimeZone() throws {
        // the scheme's test action sets TZ, so a date formatted in the local zone would slip back a day
        try #require(TimeZone.current.secondsFromGMT() < 0)

        for date in ["2024-03-01", "2024-03-01T00:30:00.000Z", "2024-03-01T23:30:00.000Z"] {
            #expect(DetailFact.movie(movie(releaseDate: date), item: nil, play: playable, state: nil)[1] == DetailFact(label: "Released", value: "1 Mar 2024"))
        }
    }

    @Test func theAudioFactPrefersTheDefaultTrack() {
        let first = MediaStream(channelLayout: "stereo", index: 1, language: "fre", type: .audio)

        #expect(audioValue(first, audio) == "English · 5.1")
    }

    @Test func theAudioFactFallsBackToTheFirstTrack() {
        let first = MediaStream(channelLayout: "stereo", index: 1, language: "fre", type: .audio)
        let second = MediaStream(channelLayout: "5.1", index: 2, language: "ger", type: .audio)

        #expect(audioValue(first, second) == "French · Stereo")
    }

    @Test func theAudioFactLeavesOutMissingChannels() {
        #expect(audioValue(MediaStream(index: 1, language: "eng", type: .audio)) == "English")
    }

    @Test func theAudioFactNamesTheLanguageOverATrackTitle() {
        #expect(audioValue(MediaStream(channelLayout: "5.1", displayTitle: "Kino - Russian - Dolby Digital - 5.1", language: "rus", type: .audio)) == "Russian · 5.1")
    }

    @Test func aDefaultSubtitleDoesNotTakeTheAudioFact() {
        #expect(audioValue(MediaStream(isDefault: true, language: "fre", type: .subtitle), audio) == "English · 5.1")
    }

    @Test(arguments: [nil, "qqq"] as [String?])
    func anAudioTrackWithoutAKnownLanguageShowsItsChannels(language: String?) {
        #expect(audioValue(MediaStream(channelLayout: "5.1", displayTitle: "Dolby Digital - 5.1", language: language, type: .audio)) == "5.1")
    }

    @Test func anUntaggedAtmosTrackShowsOnlyDolbyAtmos() {
        #expect(audioValue(MediaStream(audioSpatialFormat: .dolbyAtmos, displayTitle: "Dolby TrueHD + Dolby Atmos - 7.1", type: .audio)) == "Dolby Atmos")
    }

    @Test func anAudioTrackWithNeitherALanguageNorChannelsIsHidden() {
        #expect(audioValue(MediaStream(displayTitle: "AAC", type: .audio)) == nil)
    }

    @Test func anUndeterminedAudioLanguageReadsUnknownLanguage() {
        #expect(audioValue(MediaStream(channelLayout: "5.1", language: "und", type: .audio)) == "Unknown language · 5.1")
    }

    @Test(arguments: [
        MediaStream(audioSpatialFormat: .dolbyAtmos, channelLayout: "7.1", language: "eng", type: .audio),
        MediaStream(channelLayout: "7.1", language: "eng", profile: "Dolby TrueHD + Dolby Atmos", type: .audio),
        MediaStream(channelLayout: "7.1", language: "eng", title: "ATMOS Mix", type: .audio),
    ])
    func anAtmosTrackReadsDolbyAtmosInPlaceOfItsChannels(track: MediaStream) {
        #expect(audioValue(track) == "English · Dolby Atmos")
        #expect(badges(track) == ["ATMOS"])
    }

    @Test func oneSubtitleLanguageHasNoCount() {
        #expect(subtitlesFact([MediaStream(language: "eng", type: .subtitle)]) == DetailFact(label: "Subtitles", value: "English"))
    }

    @Test func twoSubtitleLanguagesCountTheOther() {
        #expect(subtitlesFact(["eng", "fre"].map { MediaStream(language: $0, type: .subtitle) }) == DetailFact(label: "Subtitles", value: "English", count: "+1"))
    }

    @Test func threeSubtitleLanguagesCountTheOthers() {
        #expect(subtitlesFact(["eng", "fre", "ger"].map { MediaStream(language: $0, type: .subtitle) }) == DetailFact(label: "Subtitles", value: "English", count: "+2"))
    }

    @Test func eachSubtitleLanguageCountsOnce() {
        #expect(subtitlesFact(["eng", "eng", "fre"].map { MediaStream(language: $0, type: .subtitle) }) == DetailFact(label: "Subtitles", value: "English", count: "+1"))
    }

    @Test func aSubtitleWithNoNameLeavesTheFactOut() {
        #expect(subtitlesFact([MediaStream(displayTitle: "", type: .subtitle)]) == nil)
    }

    @Test func aSubtitleWithNoNameBeforeALanguageIsNotCounted() {
        let streams = [MediaStream(displayTitle: "", type: .subtitle), MediaStream(language: "eng", type: .subtitle)]

        #expect(subtitlesFact(streams) == DetailFact(label: "Subtitles", value: "English"))
    }

    @Test func aSubtitleWithNoNameAfterALanguageIsNotCounted() {
        let streams = [MediaStream(language: "eng", type: .subtitle), MediaStream(displayTitle: "", type: .subtitle)]

        #expect(subtitlesFact(streams) == DetailFact(label: "Subtitles", value: "English"))
    }

    @Test(arguments: [nil, "qqq"] as [String?])
    func aSubtitleWithoutAKnownLanguageGoesByItsTitle(language: String?) {
        #expect(subtitlesFact([MediaStream(displayTitle: "Forced - SUBRIP", language: language, type: .subtitle)]) == DetailFact(label: "Subtitles", value: "Forced"))
    }

    @Test(arguments: [
        (2160, 0, "4K"), (0, 3800, "4K"), (2159, 3799, "1080p"), (1080, 0, "1080p"), (0, 1900, "1080p"),
    ])
    func theResolutionBadgeFollowsItsThresholds(height: Int, width: Int, badge: String) {
        #expect(badges(height: height, width: width) == [badge])
    }

    @Test func anAudioTrackBeforeTheVideoDoesNotHideItsBadge() {
        #expect(DetailFact.badges(item: item(audio, MediaStream(height: 2160, type: .video)), play: playable) == ["4K"])
    }

    @Test func aSmallerVideoHasNoResolutionBadge() {
        #expect(badges(height: 1079, width: 1899).isEmpty)
    }

    @Test func theHDRBadgeShowsOnlyForARangeThatIsNeitherSDRNorUnknown() {
        #expect(badges(range: .hdr) == ["HDR"])
        #expect(badges(range: .sdr).isEmpty)
        #expect(badges(range: .unknown).isEmpty)
        #expect(badges(range: nil).isEmpty)
    }

    @Test func theATMOSBadgeLooksAtEveryAudioTrack() {
        let atmos = MediaStream(audioSpatialFormat: .dolbyAtmos, type: .audio)

        #expect(badges(audio, atmos) == ["ATMOS"])
    }

    @Test func theATMOSBadgeIgnoresASubtitleNamingAtmos() {
        #expect(badges(MediaStream(title: "Atmos commentary", type: .subtitle)).isEmpty)
    }

    @Test(arguments: [
        ("2026-05-27", "27 May 2026" as String?), ("2025-11-28", "28 Nov 2025"), ("2025-11-27", "2025"),
        ("2026-05-28", "28 May 2026"), ("2026-12-20", "20 Dec 2026"), ("2027-05-01", "1 May 2027"),
        ("1995-12-15", "1995"), ("", nil), ("soon", "soon"),
    ] as [(String, String?)])
    func aReleaseShowsItsDayFromSixMonthsBackOn(date: String, expected: String?) {
        let now = Date(timeIntervalSince1970: 1_780_000_000) // 2026-05-28 20:26 UTC
        #expect(DetailFact.release(date, now: now) == expected)
    }

    @Test func aMissingReleaseIsNil() {
        #expect(DetailFact.release(nil) == nil)
    }

    @Test func badgesRunResolutionThenHDRThenATMOS() {
        #expect(badges(height: 2160, range: .hdr, MediaStream(audioSpatialFormat: .dolbyAtmos, type: .audio)) == ["4K", "HDR", "ATMOS"])
    }
}
