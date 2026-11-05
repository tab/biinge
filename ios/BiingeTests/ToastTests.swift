import Testing
@testable import Biinge

/// The details confirmations say what a list pick, a removal or a pin changed
struct ToastTests {
    @Test(arguments: zip([
        (WatchState?.none, WatchState?.some(.want), DetailKind.movie),
        (nil, .watching, .series),
        (nil, .want, .game),
        (.want, .watched, .movie),
        (.watching, .watched, .series),
        (.want, .playing, .game),
        (.playing, .played, .game),
        (.want, nil, .movie),
        (.watching, nil, .series),
        (.watched, nil, .series),
        (.played, nil, .game),
    ] as [(WatchState?, WatchState?, DetailKind)], [
        ("Added to Want to Watch", "bookmark.fill"),
        ("Added to Watching", "circle.lefthalf.filled"),
        ("Added to Want to Play", "bookmark.fill"),
        ("Moved to Watched", "checkmark.circle.fill"),
        ("Moved to Watched", "checkmark.circle.fill"),
        ("Moved to Playing", "gamecontroller.fill"),
        ("Moved to Played", "checkmark.circle.fill"),
        ("Removed from Want to Watch", "minus.circle.fill"),
        ("Removed from Watching", "minus.circle.fill"),
        ("Removed from Watched", "minus.circle.fill"),
        ("Removed from Played", "minus.circle.fill"),
    ]))
    func aListChangeSaysWhereTheTitleWent(change: (old: WatchState?, new: WatchState?, kind: DetailKind), expected: (message: String, systemImage: String)) throws {
        let (old, new, kind) = change
        let toast = try #require(Toast(from: old, to: new, kind: kind) {} canUndo: { true })

        #expect(toast.message == expected.message)
        #expect(toast.systemImage == expected.systemImage)
        // only a removal offers Undo
        #expect((toast.undo != nil) == (new == nil))
    }

    @Test func aMoveCarriesItsSideEffectAsASecondLine() throws {
        let toast = try #require(Toast(from: .want, to: .watched, kind: .movie, sub: "Also marked played on Living Room"))

        #expect(toast.message == "Moved to Watched")
        #expect(toast.sub == "Also marked played on Living Room")
        #expect(Toast(from: nil, to: .want, kind: .movie)?.sub == nil)
    }

    @Test func noChangeShowsNoToast() {
        #expect(Toast(from: .want, to: .want, kind: .movie) == nil)
        #expect(Toast(from: nil, to: nil, kind: .series) == nil)
    }

    @Test func aPinSaysUpNextWithoutUndo() {
        #expect(Toast(pinned: true).message == "Pinned to Up Next")
        #expect(Toast(pinned: false).message == "Unpinned from Up Next")
        #expect(Toast(pinned: true).systemImage == "pin.fill")
        #expect(Toast(pinned: false).undo == nil)
    }

    @Test func anEpisodeMarkSaysWatchedOrUnwatched() {
        #expect(Toast(episodeWatched: true).message == "Marked watched")
        #expect(Toast(episodeWatched: true).systemImage == "checkmark.circle.fill")
        #expect(Toast(episodeWatched: false).message == "Marked unwatched")
        #expect(Toast(episodeWatched: false).systemImage == nil)
    }

    @Test func aRepeatedMessageIsANewToastThatReplacesTheShowingOne() {
        #expect(Toast(episodeWatched: true) != Toast(episodeWatched: true))
    }
}
