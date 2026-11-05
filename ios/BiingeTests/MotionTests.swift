import Foundation
import ImageIO
import Testing
@testable import Biinge

/// The shared curves and durations hold the motion board's values
struct MotionTests {
    @Test func curvesMatchTheBoardsControlPoints() {
        let points = { (curve: MotionCurve) in [curve.x1, curve.y1, curve.x2, curve.y2] }

        #expect(points(.standard) == [0.2, 0.7, 0.2, 1])
        #expect(points(.exit) == [0.4, 0, 1, 1])
        #expect(points(.focus) == [0.34, 1.36, 0.64, 1])
        #expect(points(.linear) == [0, 0, 1, 1])
    }

    @Test func durationsMatchTheBoard() {
        #expect(MotionDuration.press == 0.12)
        #expect(MotionDuration.quick == 0.2)
        #expect(MotionDuration.standard == 0.28)
        #expect(MotionDuration.emphasis == 0.45)
        #expect(MotionDuration.morph == 0.55)
        #expect(MotionDuration.ambient == 0.8)
    }

    @Test func loadingTimingsMatchTheBoard() {
        // a skeleton waits 300 ms and a playback spinner 500 ms, and either holds 500 ms once shown
        #expect(MotionDuration.skeletonDelay == 0.3)
        #expect(MotionDuration.stallDelay == 0.5)
        #expect(MotionDuration.loadingHold == 0.5)
        #expect(MotionDuration.stallExit == 0.15)
        #expect(MotionDuration.shimmer == 1.4)
        #expect(MotionDuration.posterStagger == 0.04)
    }

    @Test func aStallShowsTheSpinnerAfter500Ms() {
        #expect(MotionDuration.stallWait(isBuffering: true, shownAt: nil, now: .now) == 0.5)
        #expect(MotionDuration.stallWait(isBuffering: false, shownAt: nil, now: .now) == nil)
    }

    @Test func aShownSpinnerStaysAtLeast500Ms() {
        let shownAt = Date(timeIntervalSinceReferenceDate: 0)

        #expect(MotionDuration.stallWait(isBuffering: false, shownAt: shownAt, now: shownAt) == 0.5)
        #expect(abs((MotionDuration.stallWait(isBuffering: false, shownAt: shownAt, now: shownAt.addingTimeInterval(0.1)) ?? 0) - 0.4) < 1e-9)
        #expect(MotionDuration.stallWait(isBuffering: false, shownAt: shownAt, now: shownAt.addingTimeInterval(0.5)) == 0)
        #expect(MotionDuration.stallWait(isBuffering: false, shownAt: shownAt, now: shownAt.addingTimeInterval(2)) == 0)
    }

    @Test func aStallThatReturnsKeepsTheShownSpinner() {
        #expect(MotionDuration.stallWait(isBuffering: true, shownAt: .now, now: .now) == nil)
    }

    @MainActor @Test func aSkeletonNeverShowsForALoadUnder300Ms() async throws {
        var calls: [Bool] = []
        let timing = Task { await LoadingSkeleton.time { calls.append($0) } }

        // the load lands at 100 ms, which removes the skeleton and cancels its task
        try await Task.sleep(for: .milliseconds(100))
        timing.cancel()
        await timing.value

        #expect(calls.isEmpty)
    }

    @MainActor @Test func aShownSkeletonWaits300MsAndHolds500Ms() async {
        let clock = ContinuousClock()
        let start = clock.now
        var calls: [(held: Bool, at: ContinuousClock.Instant)] = []

        // the load lands during the hold, which leaves the skeleton until the hold ends
        await LoadingSkeleton.time { calls.append(($0, clock.now)) }

        #expect(calls.map(\.held) == [true, false])
        guard calls.count == 2 else { return }
        #expect(calls[0].at - start >= .milliseconds(300))
        #expect(calls[1].at - calls[0].at >= .milliseconds(500))
    }

    @MainActor @Test func aSkeletonThatLeavesDuringItsHoldEndsTheHold() async throws {
        let clock = ContinuousClock()
        var calls: [(held: Bool, at: ContinuousClock.Instant)] = []
        let timing = Task { await LoadingSkeleton.time { calls.append(($0, clock.now)) } }
        for _ in 0..<100 where calls.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(calls.map(\.held) == [true])

        // a closed screen cancels the skeleton's task mid-hold
        timing.cancel()
        await timing.value

        #expect(calls.map(\.held) == [true, false])
        guard calls.count == 2 else { return }
        #expect(calls[1].at - calls[0].at < .milliseconds(500))
    }

    @Test func postersStaggerOverTheFirstScreenfulOnly() {
        #expect(MotionDuration.posterFadeDelay(at: 0, reduceMotion: false) == 0)
        #expect(abs(MotionDuration.posterFadeDelay(at: 1, reduceMotion: false) - 0.04) < 1e-9)
        #expect(abs(MotionDuration.posterFadeDelay(at: 11, reduceMotion: false) - 0.44) < 1e-9)
        #expect(MotionDuration.posterFadeDelay(at: 12, reduceMotion: false) == 0)
        #expect(MotionDuration.posterFadeDelay(at: 40, reduceMotion: false) == 0)
    }

    @Test func reduceMotionDropsTheStagger() {
        #expect(MotionDuration.posterFadeDelay(at: 5, reduceMotion: true) == 0)
    }

    @MainActor @Test func aListSkeletonShowsItsLastCountUpToAScreenful() {
        // a first visit fills the screen
        #expect(SkeletonRows.count(for: "test-first-visit", screenful: 6) == 6)

        SkeletonRows.counts["test-short"] = 3
        #expect(SkeletonRows.count(for: "test-short", screenful: 6) == 3)

        SkeletonRows.counts["test-long"] = 40
        #expect(SkeletonRows.count(for: "test-long", screenful: 6) == 6)

        SkeletonRows.counts["test-empty"] = 0
        #expect(SkeletonRows.count(for: "test-empty", screenful: 6) == 0)
    }

    @MainActor @Test func aSmallResizeKeepsAFixedPostersCacheKey() {
        #expect(PosterImage.maxPixel(fitting: CGSize(width: 186, height: 279)) == 600)
        #expect(PosterImage.maxPixel(fitting: CGSize(width: 190, height: 285)) == 600)
        #expect(PosterImage.maxPixel(fitting: CGSize(width: 260, height: 390)) == 800)
    }

    @Test func aPostersDecodeServesEverySmallerSize() async throws {
        // a 342 × 513 poster written as a PNG, which the shared cache loads from its file URL
        let context = try #require(CGContext(
            data: nil, width: 342, height: 513, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poster-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))

        let small = await ImageCache.shared.load(url, maxPixel: 300)
        #expect(small != nil)
        #expect(ImageCache.shared.cached(url, maxPixel: 300) === small)
        // a first layout's larger size misses, while any size finds the decode to show until the sharper one lands
        #expect(ImageCache.shared.cached(url, maxPixel: 600) == nil)
        #expect(ImageCache.shared.cached(url, maxPixel: 0) === small)

        let large = await ImageCache.shared.load(url, maxPixel: 600)
        #expect(ImageCache.shared.cached(url, maxPixel: 300) === large)
        #expect(await ImageCache.shared.load(url, maxPixel: 200) === large)
    }

    @Test func aCurveAnimatesWithItsOwnControlPointsAndDuration() {
        #expect(MotionCurve.standard.animation(0.2) == .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.2))
    }
}
