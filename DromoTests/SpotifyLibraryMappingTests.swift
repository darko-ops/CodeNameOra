import XCTest
import DromoCore
@testable import Dromo

/// Regression cover for the rule that a library with no tempo is still a library.
///
/// `savedTracks` used to require a BPM per track. Spotify restricted
/// `/v1/audio-features` for new apps, so the tempo lookup legitimately returns nothing
/// — and every saved track then failed that guard, leaving the runner's whole library
/// empty. The coordinator read the empty result as "nothing connected" and substituted
/// a demo catalog, so the failure surfaced as somebody else's music rather than as an
/// error. Tempo is needed to *pace* a song, not to *show* one.
final class SpotifyLibraryMappingTests: XCTestCase {

    private func dto(_ id: String, _ name: String, seconds: Int = 200) -> SpotifyTrackDTO {
        SpotifyTrackDTO(id: id, name: name,
                        artists: [.init(name: "Test Artist")],
                        duration_ms: seconds * 1000)
    }

    /// The exact failure: audio-features forbidden, so no tempo for anything.
    func test_librarySurvivesWhenSpotifyGivesNoTempo() {
        let dtos = [dto("1", "One"), dto("2", "Two"), dto("3", "Three")]

        let tracks = SpotifyWebAPI.tracks(from: dtos, bpmByID: [:])

        XCTAssertEqual(tracks.count, 3, "An untagged library must still be a library")
        XCTAssertEqual(tracks.map(\.title), ["One", "Two", "Three"])
        XCTAssertTrue(tracks.allSatisfy { $0.bpm == 0 },
                      "Unknown tempo is 0, which enrichment later resolves")
    }

    /// Tempo is used where it exists, and its absence doesn't cost the neighbours.
    func test_keepsKnownTempoAndUntaggedTogether() {
        let dtos = [dto("1", "Tagged"), dto("2", "Untagged")]

        let tracks = SpotifyWebAPI.tracks(from: dtos, bpmByID: ["1": 168])

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks.first { $0.id == "1" }?.bpm, 168)
        XCTAssertEqual(tracks.first { $0.id == "2" }?.bpm, 0)
    }

    /// A track with no id can't be played or looked up, so it's the one thing dropped.
    func test_dropsOnlyTracksWithNoID() {
        let dtos = [dto("1", "Playable"),
                    SpotifyTrackDTO(id: nil, name: "Unaddressable",
                                    artists: [.init(name: "X")], duration_ms: 1000)]

        let tracks = SpotifyWebAPI.tracks(from: dtos, bpmByID: [:])

        XCTAssertEqual(tracks.map(\.id), ["1"])
    }

    /// Downstream of the fix: merging must not undo it. The aggregator prefers a tagged
    /// copy of the *same* recording, which must not become "drop untagged tracks".
    func test_aggregatorKeepsUntaggedTracks() {
        let spotify = SpotifyWebAPI.tracks(from: [dto("1", "Only Copy")], bpmByID: [:])

        let merged = LibraryAggregator.merged([spotify])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.bpm, 0)
    }
}
