import XCTest
@testable import DromoCore

/// A BPM sink spy that records the keys it was asked to store under.
private actor SpyBPMSink: BPMSink {
    private(set) var stored: [String: Double] = [:]
    func store(bpm: Double, trackID: String) async { stored[trackID] = bpm }
    func store(_ finding: BPMFinding, trackID: String) async { stored[trackID] = finding.bpm }
    func keys() -> [String] { Array(stored.keys) }
}

final class CollectiveLearningTests: XCTestCase {

    private func track(_ id: String, title: String, artist: String,
                       provider: Track.MusicProvider) -> Track {
        Track(id: id, title: title, artist: artist, bpm: 120, energyLevel: 0.5,
              durationSeconds: 200, provider: provider)
    }

    /// The same recording in two apps, plus an unrelated track.
    private var aliases: RecordingAliases {
        RecordingAliases(libraries: [
            [track("apple:1", title: "One More Time", artist: "Daft Punk", provider: .appleMusic),
             track("apple:2", title: "Levee", artist: "Zeppelin", provider: .appleMusic)],
            [track("spotify:9", title: "One More Time", artist: "Daft Punk", provider: .spotify)],
        ])
    }

    // MARK: - Aliases

    func testDuplicateCopiesShareOneRecordingID() {
        let a = aliases
        XCTAssertEqual(a.recordingID(for: "apple:1"), a.recordingID(for: "spotify:9"))
        XCTAssertNotEqual(a.recordingID(for: "apple:1"), a.recordingID(for: "apple:2"))
        XCTAssertTrue(a.recordingID(for: "apple:1").hasPrefix(RecordingAliases.prefix))
    }

    func testUnknownIDResolvesToItselfAndEmptyAliasesAreIdentity() {
        XCTAssertEqual(aliases.recordingID(for: "unknown"), "unknown")
        let empty = RecordingAliases()
        XCTAssertEqual(empty.recordingID(for: "apple:1"), "apple:1")
        XCTAssertEqual(empty.expanded(["x": 1.0]), ["x": 1.0])
    }

    func testExpandedKeepsLegacyPlatformKeyedEntriesVisible() {
        let recID = aliases.recordingID(for: "apple:1")
        let expanded = aliases.expanded([recID: 0.9, "legacy:id": 0.4])
        XCTAssertEqual(expanded["apple:1"], 0.9)
        XCTAssertEqual(expanded["spotify:9"], 0.9)
        XCTAssertEqual(expanded["legacy:id"], 0.4)
    }

    // MARK: - Effectiveness across copies

    func testEffectivenessLearnedThroughOneCopyAppliesToTheOther() async {
        let store = CollectiveEffectivenessStore(base: InMemoryEffectivenessStore(),
                                                 aliases: aliases)
        await store.record(TrackResponse(trackID: "spotify:9", mode: .push,
                                         reward: 1.0, samples: 10))

        let byID = await store.effectiveness(for: .push)
        XCTAssertNotNil(byID["apple:1"], "the Apple copy inherits the Spotify copy's learning")
        XCTAssertEqual(byID["apple:1"], byID["spotify:9"])
        XCTAssertNil(byID["apple:2"], "unrelated tracks learn nothing")
    }

    func testLearningSurvivesTheOtherCopyBecomingTheSurvivor() async {
        let base = InMemoryEffectivenessStore()
        // Session 1: both sources connected, the Spotify copy plays and teaches.
        let both = CollectiveEffectivenessStore(base: base, aliases: aliases)
        await both.record(TrackResponse(trackID: "spotify:9", mode: .push,
                                        reward: 1.0, samples: 10))

        // Session 2: Spotify toggled out — only the Apple copy exists now.
        let appleOnly = RecordingAliases(libraries: [
            [track("apple:1", title: "One More Time", artist: "Daft Punk", provider: .appleMusic)],
        ])
        let later = CollectiveEffectivenessStore(base: base, aliases: appleOnly)
        let byID = await later.effectiveness(for: .push)
        XCTAssertNotNil(byID["apple:1"], "toggling the source that taught never orphans the learning")
    }

    func testBothCopiesFoldIntoOneEstimateNotTwo() async {
        let base = InMemoryEffectivenessStore()
        let store = CollectiveEffectivenessStore(base: base, aliases: aliases)
        await store.record(TrackResponse(trackID: "spotify:9", mode: .push, reward: 1.0, samples: 10))
        await store.record(TrackResponse(trackID: "apple:1", mode: .push, reward: 1.0, samples: 10))

        let learned = await store.learned(for: .push)
        XCTAssertEqual(learned["apple:1"]?.observations, 2,
                       "plays through different apps accumulate on the same recording")
        let underlying = await base.learned(for: .push)
        XCTAssertEqual(underlying.count, 1, "one recording, one stored estimate")
    }

    // MARK: - Preferences across copies

    func testLikeThroughOneCopyWeighsTheOther() async {
        let store = CollectivePreferenceStore(base: InMemoryPreferenceStore(), aliases: aliases)
        await store.record(.liked, trackID: "apple:1")

        let weights = await store.weights()
        XCTAssertEqual(weights["spotify:9"], weights["apple:1"])
        XCTAssertNil(weights["apple:2"])
    }

    // MARK: - Enrichment across copies

    func testBPMStoresOncePerRecordingWhicheverCopyWasLookedUp() async {
        let spy = SpyBPMSink()
        let sink = CollectiveBPMSink(base: spy, aliases: aliases)
        await sink.store(bpm: 123, trackID: "spotify:9")
        await sink.store(bpm: 123, trackID: "apple:1")

        let keys = await spy.keys()
        XCTAssertEqual(keys, [aliases.recordingID(for: "apple:1")],
                       "both copies write the same single recording key")
    }
}
