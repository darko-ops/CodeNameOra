import XCTest
@testable import DromoCore

final class LibraryAggregatorTests: XCTestCase {

    private func track(_ id: String, title: String, artist: String, bpm: Double,
                       provider: Track.MusicProvider = .appleMusic) -> Track {
        Track(id: id, title: title, artist: artist, bpm: bpm, energyLevel: 0.5,
              durationSeconds: 200, provider: provider)
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
}
