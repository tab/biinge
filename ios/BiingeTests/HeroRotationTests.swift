import Foundation
import Testing
@testable import Biinge

struct HeroRotationTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    /// A rotation whose clock runs from `start`
    private func running() -> HeroRotation {
        var rotation = HeroRotation()
        rotation.resume(at: start)
        return rotation
    }

    @Test func advancesAfterNineSeconds() {
        var rotation = running()

        let early = rotation.advance(count: 3, at: start + 8.9)
        #expect(!early)
        #expect(rotation.index == 0)
        let first = rotation.advance(count: 3, at: start + 9)
        #expect(first)
        #expect(rotation.index == 1)
        let earlyAgain = rotation.advance(count: 3, at: start + 17.9)
        #expect(!earlyAgain)
        let second = rotation.advance(count: 3, at: start + 18)
        #expect(second)
        #expect(rotation.index == 2)
    }

    @Test func holdsWhileFocusIsBelowTheHero() {
        var rotation = running()

        rotation.pause(at: start + 4)
        let whilePaused = rotation.advance(count: 3, at: start + 60)
        #expect(!whilePaused)
        #expect(rotation.elapsed(at: start + 60) == 4)
        rotation.resume(at: start + 60)
        let early = rotation.advance(count: 3, at: start + 64.9)
        #expect(!early)
        let turned = rotation.advance(count: 3, at: start + 65)
        #expect(turned)
        #expect(rotation.index == 1)
    }

    @Test func countsNothingBeforeTheFirstResume() {
        var rotation = HeroRotation()

        let turned = rotation.advance(count: 3, at: start + 60)
        #expect(!turned)
        #expect(rotation.elapsed(at: start + 60) == 0)
    }

    @Test func aTurnByHandStartsTheNineSecondsOver() {
        var rotation = running()

        rotation.turn(to: 2, at: start + 6)
        let early = rotation.advance(count: 3, at: start + 14.9)
        #expect(!early)
        let turned = rotation.advance(count: 3, at: start + 15)
        #expect(turned)
        #expect(rotation.index == 0)
    }

    @Test func aTurnWhilePausedCountsFromTheResume() {
        var rotation = running()

        rotation.pause(at: start + 4)
        rotation.turn(to: 1, at: start + 10)
        rotation.resume(at: start + 20)
        #expect(rotation.elapsed(at: start + 20) == 0)
        let early = rotation.advance(count: 3, at: start + 28.9)
        #expect(!early)
        let turned = rotation.advance(count: 3, at: start + 29)
        #expect(turned)
        #expect(rotation.index == 2)
    }

    @Test func wrapsAfterTheLastPage() {
        var rotation = running()

        rotation.turn(to: 1, at: start)
        let turned = rotation.advance(count: 2, at: start + 9)
        #expect(turned)
        #expect(rotation.index == 0)
    }

    @Test func aRowAReloadShortenedWrapsFromItsLastPage() {
        var rotation = running()

        rotation.turn(to: 4, at: start)
        let turned = rotation.advance(count: 2, at: start + 9)
        #expect(turned)
        #expect(rotation.index == 0)
    }

    @Test func oneFeaturedTitleNeverTurns() {
        var rotation = running()

        let turned = rotation.advance(count: 1, at: start + 60)
        #expect(!turned)
        #expect(rotation.index == 0)
    }
}
