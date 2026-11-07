import Foundation
import Testing
@testable import Biinge

struct DetailsDecodingTests {
    private let movie = #"{"id": 10, "title": "Heat", "posterPath": "", "pinned": false, "state": "none", "overview": "", "genres": [], "credits": [], "recommendations": [], "videos": []"#
    private let series =
        #"{"id": 20, "title": "Show", "posterPath": "", "pinned": false, "state": "none", "overview": "", "genres": [], "credits": [], "recommendations": [], "videos": [], "seasons": []"#
    private let episodeSummary = #"{"id": 5, "title": "Pilot", "number": 1, "posterPath": "", "overview": "", "runtime": 50"#
    private let episodeDetails = #"{"id": 5, "title": "Pilot", "number": 1, "posterPath": "", "runtime": 50, "overview": "", "credits": [], "videos": []"#
    private let game = #"{"id": 30, "title": "Hades", "posterPath": "", "pinned": false, "state": "none", "overview": "", "genres": [], "platforms": []"#

    /// The JSON object opened by `prefix`, closed with or without a jellyfinId
    private func json(_ prefix: String, jellyfinID: String?) -> Data {
        Data((prefix + (jellyfinID.map { #", "jellyfinId": "\#($0)"}"# } ?? "}")).utf8)
    }

    @Test(arguments: ["j1", nil] as [String?])
    func jellyfinIDIsSetWhenPresentAndNilWhenAbsent(jellyfinID: String?) throws {
        let decoder = JSONDecoder()

        #expect(try decoder.decode(MovieDetails.self, from: json(movie, jellyfinID: jellyfinID)).jellyfinID == jellyfinID)
        #expect(try decoder.decode(SeriesDetails.self, from: json(series, jellyfinID: jellyfinID)).jellyfinID == jellyfinID)
        #expect(try decoder.decode(EpisodeSummary.self, from: json(episodeSummary, jellyfinID: jellyfinID)).jellyfinID == jellyfinID)
        #expect(try decoder.decode(EpisodeDetails.self, from: json(episodeDetails, jellyfinID: jellyfinID)).jellyfinID == jellyfinID)
    }

    @Test func genresDecodeOnMovieAndSeriesDetails() throws {
        let decoder = JSONDecoder()
        let genres = #""genres": ["Drama", "Thriller"]"#

        #expect(try decoder.decode(MovieDetails.self, from: Data((movie.replacingOccurrences(of: #""genres": []"#, with: genres) + "}").utf8)).genres == ["Drama", "Thriller"])
        #expect(try decoder.decode(SeriesDetails.self, from: Data((series.replacingOccurrences(of: #""genres": []"#, with: genres) + "}").utf8)).genres == ["Drama", "Thriller"])
    }

    @Test func namesDecodeWhenPresent() throws {
        let decoder = JSONDecoder()

        #expect(try decoder.decode(MovieDetails.self, from: Data((movie + #", "directors": ["Michael Mann"]}"#).utf8)).directors == ["Michael Mann"])
        #expect(try decoder.decode(SeriesDetails.self, from: Data((series + #", "creators": ["Vince Gilligan"]}"#).utf8)).creators == ["Vince Gilligan"])
        #expect(try decoder.decode(EpisodeDetails.self, from: Data((episodeDetails + #", "directors": ["Mike Judge"]}"#).utf8)).directors == ["Mike Judge"])
        #expect(try decoder.decode(GameDetails.self, from: Data((game + #", "developers": ["CD Projekt RED"]}"#).utf8)).developers == ["CD Projekt RED"])
    }

    @Test func namesStayNilWhenTheAPIOmitsThem() throws {
        let decoder = JSONDecoder()

        #expect(try decoder.decode(MovieDetails.self, from: Data((movie + "}").utf8)).directors == nil)
        #expect(try decoder.decode(SeriesDetails.self, from: Data((series + "}").utf8)).creators == nil)
        #expect(try decoder.decode(EpisodeDetails.self, from: Data((episodeDetails + "}").utf8)).directors == nil)
        #expect(try decoder.decode(GameDetails.self, from: Data((game + "}").utf8)).developers == nil)
    }

    @Test(arguments: ["An actor.", nil] as [String?])
    func biographyIsSetWhenPresentAndNilWhenAbsent(biography: String?) throws {
        let prefix = #"{"id": 30, "name": "Ryan Gosling", "profilePath": "", "gender": 2, "movieCredits": [], "seriesCredits": []"#
        let data = Data((prefix + (biography.map { #", "biography": "\#($0)"}"# } ?? "}")).utf8)

        #expect(try JSONDecoder().decode(PersonDetails.self, from: data).biography == biography)
    }
}
