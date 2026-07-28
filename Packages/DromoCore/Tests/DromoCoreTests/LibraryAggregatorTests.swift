import XCTest
@testable import DromoCore

final class LibraryAggregatorTests: XCTestCase {

    private func track(_ id: String, title: String, artist: String, bpm: Double,
                       provider: Track.MusicProvider = .appleMusic,
                       seconds: Int = 200) -> Track {
        Track(id: id, title: title, artist: artist, bpm: bpm, energyLevel: 0.5,
              durationSeconds: seconds, provider: provider)
    }

    func testDistinctTracksFromAllSourcesAreRetainedInSourceOrder() {
        let apple = [track("a1", title: "One", artist: "A", bpm: 120)]
        let spotify = [track("s1", title: "Two", artist: "B", bpm: 150, provider: .spotify)]

        let merged = LibraryAggregator.merged([apple, spotify])

        XCTAssertEqual(merged.map(\.id), ["a1", "s1"])
    }

    func testSameRecordingAcrossSourcesCollapsesToFirstConnected() {
        let apple = [track("a1", title: "One More Time", artist: "Daft Punk", bpm: 123)]
        let spotify = [track("s1", title: "One More Time", artist: "Daft Punk", bpm: 123,
                             provider: .spotify)]

        let merged = LibraryAggregator.merged([apple, spotify])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, "a1")
    }

    func testTempoBearingCopyReplacesTempolessOneRegardlessOfOrder() {
        let spotify = [track("s1", title: "Song", artist: "X", bpm: 0, provider: .spotify)]
        let apple = [track("a1", title: "Song", artist: "X", bpm: 128)]

        let merged = LibraryAggregator.merged([spotify, apple])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, "a1")
        XCTAssertEqual(merged[0].bpm, 128)
    }

    func testTempolessCopyNeverReplacesTempoBearingOne() {
        let apple = [track("a1", title: "Song", artist: "X", bpm: 128)]
        let spotify = [track("s1", title: "Song", artist: "X", bpm: 0, provider: .spotify)]

        let merged = LibraryAggregator.merged([apple, spotify])

        XCTAssertEqual(merged.map(\.id), ["a1"])
    }

    func testDedupeKeyFoldsCaseAndWhitespaceButKeepsVariantsDistinct() {
        XCTAssertEqual(LibraryAggregator.dedupeKey(title: "One  More Time", artist: "DAFT PUNK"),
                       LibraryAggregator.dedupeKey(title: "one more time", artist: "Daft Punk"))
        XCTAssertNotEqual(LibraryAggregator.dedupeKey(title: "One More Time (Live)", artist: "Daft Punk"),
                          LibraryAggregator.dedupeKey(title: "One More Time", artist: "Daft Punk"))
    }

    func testEmptyAndSingleSourcePassThrough() {
        XCTAssertTrue(LibraryAggregator.merged([]).isEmpty)
        let apple = [track("a1", title: "One", artist: "A", bpm: 120)]
        XCTAssertEqual(LibraryAggregator.merged([apple]).map(\.id), ["a1"])
    }

    // MARK: - Same title, different recording

    func testLiveAndStudioCutsWithTheSameTitleStayApart() {
        // Both "Purple Rain" by Prince; the live one runs four minutes longer and at a
        // different tempo. Merging them would pace a runner to a tempo they never ran to.
        let studio = track("a1", title: "Purple Rain", artist: "Prince", bpm: 113, seconds: 258)
        let live = track("s1", title: "Purple Rain", artist: "Prince", bpm: 108,
                         provider: .spotify, seconds: 502)

        let merged = LibraryAggregator.merged([[studio], [live]])

        XCTAssertEqual(merged.count, 2, "different runtimes ⇒ different recordings")
        XCTAssertEqual(Set(merged.map(\.bpm)), [113, 108])
    }

    func testCrossServiceJitterStillCountsAsOneRecording() {
        // Services rarely agree to the second; a couple of seconds must not split a song.
        let apple = track("a1", title: "One More Time", artist: "Daft Punk", bpm: 123, seconds: 320)
        let spotify = track("s1", title: "One More Time", artist: "Daft Punk", bpm: 123,
                            provider: .spotify, seconds: 323)

        XCTAssertEqual(LibraryAggregator.merged([[apple], [spotify]]).count, 1)
    }

    func testUnknownRuntimeNeverSplitsARecording() {
        // Missing metadata is not evidence of a different recording.
        let known = track("a1", title: "Song", artist: "A", bpm: 120, seconds: 240)
        let unknown = track("s1", title: "Song", artist: "A", bpm: 120,
                            provider: .spotify, seconds: 0)

        XCTAssertEqual(LibraryAggregator.merged([[known], [unknown]]).count, 1)
    }

    // MARK: - Recording ids

    func testSingleRecordingKeepsTheBareKeySoLearnedDataStaysAttached() {
        // The overwhelmingly common case must produce exactly the pre-split id, or
        // every runner would silently lose what the app already learned.
        let apple = track("a1", title: "One", artist: "A", bpm: 120, seconds: 200)
        let spotify = track("s1", title: "One", artist: "A", bpm: 120,
                            provider: .spotify, seconds: 201)

        let ids = LibraryAggregator.recordingIDs([[apple], [spotify]])

        XCTAssertEqual(ids["a1"], LibraryAggregator.dedupeKey(title: "One", artist: "A"))
        XCTAssertEqual(ids["s1"], ids["a1"])
    }

    func testOnlyTheLongerRecordingTakesTheSuffix() {
        let studio = track("a1", title: "Song", artist: "A", bpm: 120, seconds: 240)
        let live = track("s1", title: "Song", artist: "A", bpm: 110,
                         provider: .spotify, seconds: 600)

        let ids = LibraryAggregator.recordingIDs([[studio], [live]])

        XCTAssertEqual(ids["a1"], LibraryAggregator.dedupeKey(title: "Song", artist: "A"),
                       "the shorter/original keeps the id its history is stored under")
        XCTAssertEqual(ids["s1"], ids["a1"]! + "|alt1")
    }

    func testRecordingIDsDoNotDependOnConnectionOrder() {
        let studio = track("a1", title: "Song", artist: "A", bpm: 120, seconds: 240)
        let live = track("s1", title: "Song", artist: "A", bpm: 110,
                         provider: .spotify, seconds: 600)

        XCTAssertEqual(LibraryAggregator.recordingIDs([[studio], [live]]),
                       LibraryAggregator.recordingIDs([[live], [studio]]),
                       "toggling sources in a different order must not re-key learning")
    }

    func testAliasesSplitTheSameWayTheLibraryDoes() {
        let studio = track("a1", title: "Song", artist: "A", bpm: 120, seconds: 240)
        let live = track("s1", title: "Song", artist: "A", bpm: 110,
                         provider: .spotify, seconds: 600)
        let aliases = RecordingAliases(libraries: [[studio], [live]])

        XCTAssertNotEqual(aliases.recordingID(for: "a1"), aliases.recordingID(for: "s1"),
                          "what the runner sees as two songs must learn as two songs")
    }
}
