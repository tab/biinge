import Foundation
import JellyfinAPI
import Testing
@testable import Biinge

struct TrackLabelTests {
    @Test func anAudioTrackSplitsIntoItsLanguageAndTheRest() {
        let label = TrackLabel(MediaStream(displayTitle: "English - Dolby Digital - 5.1 - Default", index: 1, type: .audio))

        #expect(label == TrackLabel(title: "English", detail: "Dolby Digital · 5.1 · Default"))
    }

    @Test func aSubtitleTrackWithOnlyALanguageHasNoDetail() {
        let label = TrackLabel(MediaStream(displayTitle: "Français", index: 3, type: .subtitle))

        #expect(label == TrackLabel(title: "Français", detail: nil))
    }

    @Test func aTrackWithoutATitleIsNamedByItsIndex() {
        let label = TrackLabel(MediaStream(index: 4, type: .subtitle))

        #expect(label == TrackLabel(title: "Track 4", detail: nil))
    }

    @Test func aTrackWithoutATitleOrAnIndexIsTrackZero() {
        #expect(TrackLabel(MediaStream(type: .subtitle)) == TrackLabel(title: "Track 0", detail: nil))
    }
}
