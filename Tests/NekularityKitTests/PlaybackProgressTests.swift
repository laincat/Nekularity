import Foundation
import Testing

@testable import NekularityKit

@Suite("Playback progress")
struct PlaybackProgressTests {
    @Test(arguments: [
        // ticks, seconds
        (Int64(0), 0),
        (10_000_000, 1),
        (1_255_000_000, 125),
        (2_700_000_000, 270),
    ])
    func ticksToSeconds(ticks: Int64, seconds: Int) {
        #expect(PlaybackProgress.seconds(fromTicks: ticks) == seconds)
    }

    @Test(arguments: [0.0, 1.0, 125.5, 3_600.0])
    func secondsSurviveTheRoundTrip(seconds: Double) {
        let ticks = PlaybackProgress.ticks(fromSeconds: seconds)
        #expect(PlaybackProgress.seconds(fromTicks: ticks) == Int(seconds.rounded(.down))
                || PlaybackProgress.seconds(fromTicks: ticks) == Int(seconds.rounded()))
    }

    @Test(arguments: [
        // position, duration, fraction
        (0.0, 100.0, 0.0),
        (50.0, 100.0, 0.5),
        (100.0, 100.0, 1.0),
        (150.0, 100.0, 1.0),      // clamped, not 1.5
        (-5.0, 100.0, 0.0),       // clamped, not negative
        (5.0, 0.0, 0.0),          // unknown length is not a position
        (5.0, .nan, 0.0),
        (5.0, .infinity, 0.0),
    ])
    func fractions(position: Double, duration: Double, expected: Double) {
        #expect(PlaybackProgress.fraction(position: position, duration: duration) == expected)
    }

    @Test("a percent is nil when the length is unknown, because 0% would be a claim")
    func percent() {
        #expect(PlaybackProgress.percent(position: 25, duration: 100) == 25)
        #expect(PlaybackProgress.percent(position: 0, duration: 0) == nil)
        #expect(PlaybackProgress.percent(position: 99.6, duration: 100) == 100)
    }

    @Test("resumable excludes the opening seconds and the credits")
    func resumable() {
        #expect(!PlaybackProgress.isResumable(position: 2, duration: 600))
        #expect(PlaybackProgress.isResumable(position: 120, duration: 600))
        #expect(!PlaybackProgress.isResumable(position: 595, duration: 600))
        // Unknown length: the caller cannot tell finished from barely started.
        #expect(!PlaybackProgress.isResumable(position: 120, duration: 0))
    }

    @Test(arguments: [
        (0.0, "0:00"),
        (5.0, "0:05"),
        (65.0, "1:05"),
        (3_723.0, "1:02:03"),
        (-1.0, "0:00"),
        (Double.nan, "0:00"),
    ])
    func clock(seconds: Double, expected: String) {
        #expect(PlaybackProgress.clock(seconds) == expected)
    }
}
