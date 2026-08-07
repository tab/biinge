import Foundation
import Testing
@testable import Biinge

struct GameDetailsTests {
    private func decode(_ json: String) throws -> GameDetails {
        try JSONDecoder().decode(GameDetails.self, from: Data(json.utf8))
    }

    @Test func decodesAFullDetailPayload() throws {
        let game = try decode("""
        {
          "id": 1942, "title": "The Witcher 3", "posterPath": "co1wyy", "pinned": false,
          "state": "playing", "overview": "A monster hunter searches for his adopted daughter.",
          "status": "Released", "releaseDate": "2015-05-19", "runtime": 3000,
          "runtimeCompleted": 6360, "rating": 9.4,
          "genres": ["RPG", "Adventure"], "platforms": ["PS5", "PS4", "PC"],
          "recommendations": [{"id": 26192, "title": "The Last of Us Part II", "posterPath": "co2", "state": "want"}]
        }
        """)

        #expect(game.id == 1942)
        #expect(game.state == .playing)
        #expect(game.genres == ["RPG", "Adventure"])
        #expect(game.platforms == ["PS5", "PS4", "PC"])
        #expect(game.recommendations.count == 1)
        #expect(game.recommendations[0].state == .want)
        #expect(game.runtimeCompleted == 6360)
    }

    // POST /games and PATCH /games/{id} acknowledge state only, so every optional field is absent and
    // the required arrays come back empty. The store discards the value but the client still decodes it
    @Test func decodesTheAcknowledgementAWriteReturns() throws {
        let game = try decode("""
        {
          "id": 1942, "title": "", "posterPath": "", "pinned": true, "state": "played",
          "overview": "", "genres": [], "platforms": [], "recommendations": []
        }
        """)

        #expect(game.state == .played)
        #expect(game.pinned)
        #expect(game.status == nil)
        #expect(game.runtime == nil)
        #expect(game.genres.isEmpty)
        #expect(game.platforms.isEmpty)
        #expect(game.recommendations.isEmpty)
    }

    // an API deployed before the recommendations rail omits the key entirely
    @Test func absentRecommendationsDecodeAsEmpty() throws {
        let game = try decode("""
        {
          "id": 1942, "title": "The Witcher 3", "posterPath": "co1wyy", "pinned": false,
          "state": "none", "overview": "", "genres": [], "platforms": []
        }
        """)

        #expect(game.recommendations.isEmpty)
    }
}
