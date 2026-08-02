import XCTest
import DromoCore
@testable import Dromo

/// Cover for tempo lookup being configured at all.
///
/// The enrichment chain omits a source whose credentials are missing, which is right —
/// but it meant a build with no usable source ran a pass that could never answer, with
/// nothing on screen to say why. Tracks stayed untagged and a slow lookup was
/// indistinguishable from an impossible one.
final class TempoSourceTests: XCTestCase {

    /// The reported state: Spotify configured, everything else blank. Spotify's
    /// audio-features is restricted for new apps, so this is close to no source at all —
    /// but it is a source, and the honest answer is that a lookup can be attempted.
    func test_spotifyOnlyStillCountsAsALookup() {
        let sources = TempoSources.current(
            getSongBPMKey: "", spotifyClientID: "abc", spotifyClientSecret: "def",
            trackTableConfigured: false)

        XCTAssertTrue(sources.canLookUpTempo)
        XCTAssertNil(sources.unavailableReason)
    }

    /// Nothing configured: the state that has to be visible rather than silent.
    func test_noSourcesIsReportedNotSilent() {
        let sources = TempoSources.current(
            getSongBPMKey: "", spotifyClientID: "", spotifyClientSecret: "",
            trackTableConfigured: false)

        XCTAssertFalse(sources.canLookUpTempo)
        XCTAssertNotNil(sources.unavailableReason,
                        "A library that can never be tagged must say so")
    }

    /// A GetSongBPM key alone is enough — it needs no audio and no ISRC, so it's the
    /// one source that works for a DRM streaming library.
    func test_getSongBPMKeyAloneEnablesLookup() {
        let sources = TempoSources.current(
            getSongBPMKey: "a-real-key", spotifyClientID: "", spotifyClientSecret: "",
            trackTableConfigured: false)

        XCTAssertTrue(sources.hasGetSongBPM)
        XCTAssertTrue(sources.canLookUpTempo)
        XCTAssertNil(sources.unavailableReason)
    }

    /// Half a Spotify credential is not a credential.
    func test_partialSpotifyCredentialsDoNotCount() {
        let sources = TempoSources.current(
            getSongBPMKey: "", spotifyClientID: "abc", spotifyClientSecret: "",
            trackTableConfigured: false)

        XCTAssertFalse(sources.hasSpotify)
        XCTAssertFalse(sources.canLookUpTempo)
    }
}

/// Cover for reading a tempo out of GetSongBPM's payload.
///
/// The API answers a hit and a miss with different shapes under the same `search` key,
/// so the parse has to tolerate both rather than throw.
final class GetSongBPMParsingTests: XCTestCase {

    func test_readsTempoFromAHit() {
        let json = Data("""
        {"search":[{"song_title":"Midnight City","tempo":"105"}]}
        """.utf8)

        XCTAssertEqual(GetSongBPMClient.parseTempo(from: json), 105)
    }

    /// A miss returns an error object where the array would be — it must read as "no
    /// tempo", not as a crash or a bogus number.
    func test_missYieldsNoTempo() {
        let json = Data("""
        {"search":{"error":"no result"}}
        """.utf8)

        XCTAssertNil(GetSongBPMClient.parseTempo(from: json))
    }

    /// Takes the first usable value, skipping entries with no tempo.
    func test_skipsEntriesWithoutATempo() {
        let json = Data("""
        {"search":[{"tempo":null},{"tempo":"0"},{"tempo":"128"}]}
        """.utf8)

        XCTAssertEqual(GetSongBPMClient.parseTempo(from: json), 128)
    }

    /// An empty key can't be used, so the client must not spend a request on it.
    func test_emptyKeyReturnsNilWithoutARequest() async {
        let client = GetSongBPMClient(apiKey: "")

        let bpm = await client.bpm(title: "Any", artist: "Any")

        XCTAssertNil(bpm)
    }
}
