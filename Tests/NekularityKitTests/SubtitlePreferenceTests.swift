import Foundation
import Testing

@testable import NekularityKit

/// The default subtitle follows the system language unless the person chose one
/// in the player; turning subtitles off is remembered as a choice too.
@Suite("Subtitle preference")
struct SubtitlePreferenceTests {
    private struct Track: Equatable {
        let id: Int
        let language: String?
    }

    private let tracks = [
        Track(id: 1, language: "en"),
        Track(id: 2, language: "zh-Hans"),
        Track(id: 3, language: "zh-Hant"),
        Track(id: 4, language: "ja"),
    ]

    @Test func systemOrderDecidesTheDefault() {
        let langs = SubtitlePreference.system.languages(system: ["zh-Hans-CN", "en-US"])
        #expect(langs == ["zh-Hans", "en"])
        #expect(SubtitlePreference.pick(tracks, languages: langs, language: \.language)?.id == 2)
    }

    @Test func aChoiceInThePlayerOverridesTheSystem() {
        let chosen = SubtitlePreference(stored: "en")
        let langs = chosen.languages(system: ["zh-Hans-CN"])
        #expect(langs == ["en"])
        #expect(SubtitlePreference.pick(tracks, languages: langs, language: \.language)?.id == 1)
    }

    @Test func offIsRememberedAndPicksNothing() {
        let off = SubtitlePreference(stored: "off")
        #expect(off == .off)
        #expect(off.languages(system: ["en"]).isEmpty)
        #expect(SubtitlePreference.pick(tracks, languages: off.languages(), language: \.language) == nil)
    }

    @Test func storedFormRoundTrips() {
        for value in [SubtitlePreference.system, .off, .language("ja"), .language("zh-Hant")] {
            #expect(SubtitlePreference(stored: value.stored) == value)
        }
    }

    @Test func chineseKeepsItsScriptAndInfersItFromTheRegion() {
        #expect(SubtitlePreference.normalise("zh-Hant-TW") == "zh-Hant")
        #expect(SubtitlePreference.normalise("zh-TW") == "zh-Hant")
        #expect(SubtitlePreference.normalise("zh-HK") == "zh-Hant")
        #expect(SubtitlePreference.normalise("zh-CN") == "zh-Hans")
        #expect(SubtitlePreference.normalise("zh_Hans") == "zh-Hans")
        #expect(SubtitlePreference.normalise("en-GB") == "en")
        #expect(SubtitlePreference.normalise("") == nil)
    }

    /// A Traditional reader is not given the Simplified track just because both
    /// are Chinese; an unscripted `zh` track is still accepted for either.
    @Test func theWrongChineseScriptIsNotAMatch() {
        let simplifiedOnly = [Track(id: 2, language: "zh-Hans"), Track(id: 1, language: "en")]
        let langs = SubtitlePreference.system.languages(system: ["zh-Hant-TW", "en"])
        #expect(SubtitlePreference.pick(simplifiedOnly, languages: langs, language: \.language)?.id == 1)

        let plain = [Track(id: 9, language: "zh"), Track(id: 1, language: "en")]
        #expect(SubtitlePreference.pick(plain, languages: langs, language: \.language)?.id == 9)
    }

    @Test func noMatchingTrackLeavesSubtitlesOff() {
        let langs = SubtitlePreference.system.languages(system: ["fr-FR"])
        #expect(SubtitlePreference.pick(tracks, languages: langs, language: \.language) == nil)
    }

    @Test func untaggedTracksAreNeverPickedByLanguage() {
        let untagged = [Track(id: 5, language: nil), Track(id: 6, language: "")]
        #expect(SubtitlePreference.pick(untagged, languages: ["en"], language: \.language) == nil)
    }
}
