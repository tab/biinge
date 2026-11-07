import Foundation
import Testing
@testable import Biinge

struct PlayNoteTests {
    @Test(arguments: ["iPhone", "Mac", "Apple TV"])
    func theConnectNoteNamesThisDevice(device: String) {
        let note = PlayNote(play: .connect, server: "Living Room", device: device)

        #expect(note?.kind == .connect)
        #expect(note?.text == "Jellyfin isn’t connected on this \(device), so Play isn’t available.")
        #expect(note?.systemImage == "link")
    }

    @Test func theNotesNameTheServer() {
        #expect(PlayNote(play: .notOnServer, server: "Living Room")?.text == "Not on Living Room. Add it to Jellyfin to play here.")
        #expect(PlayNote(play: .notOnServer, server: "Living Room")?.systemImage == "server.rack")
        #expect(PlayNote(play: .unreachable("j1"), server: "Living Room")?.text == "Can’t reach Living Room.")
        #expect(PlayNote(play: .unreachable("j1"), server: "Living Room")?.systemImage == "icloud.slash")
    }

    @Test func aServerWithoutANameIsTheServer() {
        #expect(PlayNote(play: .notOnServer, server: nil)?.text == "Not on server. Add it to Jellyfin to play here.")
    }

    @Test func aPlayHasANoteOnlyWhenJellyfinPlayedWhatWatchedLacks() {
        #expect(PlayNote(play: .play("j1"), server: "Living Room") == nil)

        let note = PlayNote(play: .play("j1"), server: "Living Room", playedUnwatched: true)

        #expect(note?.kind == .playedUnwatched)
        #expect(note?.text == "Played on Living Room, not in your Watched list.")
        #expect(note?.systemImage == "checkmark")
    }

    @Test func theSeasonNoteNamesTheNextEpisodeAndItsSeason() {
        let note = PlayNote.seasonNotOnServer(season: 3, episode: 2, server: "Living Room")

        #expect(note.text == "You’re up to S3 · E2. Season 3 isn’t on Living Room.")
        #expect(note.systemImage == "server.rack")
    }

    @Test func theSeasonNoteOfAServerWithoutANameSaysServer() {
        #expect(PlayNote.seasonNotOnServer(season: 3, episode: 2, server: nil).text == "You’re up to S3 · E2. Season 3 isn’t on server.")
    }

    @Test func theAirsNoteNeedsADay() throws {
        let note = try #require(PlayNote.airs(season: 2, episode: 1, airDate: "2026-11-10"))

        #expect(note.text.hasPrefix("You’re caught up. S2 · E1 airs "))
        #expect(note.systemImage == "calendar")
        #expect(PlayNote.airs(season: 2, episode: 1, airDate: "") == nil)
    }
}
