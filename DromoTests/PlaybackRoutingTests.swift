import XCTest
import DromoCore
@testable import Dromo

/// Regression cover for browsing playback picking the wrong song.
///
/// `NowPlayingController` queued everything through `MPMusicPlayerController`, which can
/// only hold local media-library items. It resolved tracks with
/// `UInt64($0.id)` — fine for a media-library `persistentID`, nil for Spotify's base-62
/// ids — so Spotify tracks silently dropped out of the queue while the tapped index kept
/// its original position. Everything after a dropped track shifted up, and choosing a
/// Spotify song played whichever Apple Music song landed on that index.
///
/// These test the queue arithmetic that produced the wrong song. The audio path itself
/// needs a device with both services, so it isn't asserted here.
@MainActor
final class PlaybackRoutingTests: XCTestCase {

    private func appleTrack(_ id: UInt64, _ title: String) -> Track {
        Track(id: String(id), title: title, artist: "A", bpm: 120,
              energyLevel: 0.5, durationSeconds: 200, provider: .appleMusic)
    }

    private func spotifyTrack(_ id: String, _ title: String) -> Track {
        Track(id: id, title: title, artist: "A", bpm: 0,
              energyLevel: 0.5, durationSeconds: 200, provider: .spotify)
    }

    /// The root cause: a Spotify track must never be handed to the system music player.
    /// It can only queue local media-library items, so it either dropped the track or
    /// played a neighbour in its place.
    func test_spotifyNeverRoutesToTheSystemPlayer() {
        let np = NowPlayingController()

        XCTAssertFalse(np.playsThroughSystemLibrary(spotifyTrack("4cOdK2wGLETKBW3PvgPWqT", "S")),
                       "Spotify audio cannot come from MPMusicPlayerController")
        XCTAssertTrue(np.playsThroughSystemLibrary(appleTrack(12345, "A")),
                      "A media-library persistentID is exactly what it can play")
    }

    /// An Apple Music track whose id isn't a media-library persistentID has nothing to
    /// resolve to, so it must not be queued positionally against one either.
    func test_unresolvableAppleIDDoesNotRouteToTheSystemPlayer() {
        let np = NowPlayingController()
        let catalogStyleID = Track(id: "i.AbCdEfG", title: "Cloud", artist: "A", bpm: 120,
                                   energyLevel: 0.5, durationSeconds: 200,
                                   provider: .appleMusic)

        XCTAssertFalse(np.playsThroughSystemLibrary(catalogStyleID))
    }

    /// A mixed list, tapping the Spotify entry.
    func test_choosingASpotifyTrackDoesNotPlayAnAppleMusicOne() {
        let np = NowPlayingController()
        let mixed = [appleTrack(1, "Apple One"),
                     spotifyTrack("4cOdK2wGLETKBW3PvgPWqT", "Spotify Two"),
                     appleTrack(3, "Apple Three")]

        np.play(tracks: mixed, startAt: 1)

        XCTAssertEqual(np.current?.id, "4cOdK2wGLETKBW3PvgPWqT",
                       "The tapped track must be the current one")
        XCTAssertEqual(np.current?.provider, .spotify,
                       "A Spotify choice must not resolve to an Apple Music track")
    }

    /// The queue follows the service you picked from, so "up next" can't wander into
    /// tracks that engine can't play.
    func test_queueHoldsOnlyTheChosenService() {
        let np = NowPlayingController()
        let mixed = [appleTrack(1, "Apple One"),
                     spotifyTrack("s1", "Spotify One"),
                     spotifyTrack("s2", "Spotify Two"),
                     appleTrack(2, "Apple Two")]

        np.play(tracks: mixed, startAt: 1)

        XCTAssertEqual(np.queue.map(\.id), ["s1", "s2"])
        XCTAssertEqual(np.index, 0)
    }

    /// Tapping an Apple Music entry in a mixed list still lands on that entry, not on
    /// the one that used to shift into its index.
    func test_appleMusicChoiceKeepsItsOwnPosition() {
        let np = NowPlayingController()
        let mixed = [spotifyTrack("s1", "Spotify One"),
                     appleTrack(11, "Apple One"),
                     appleTrack(22, "Apple Two")]

        np.play(tracks: mixed, startAt: 2)

        XCTAssertEqual(np.current?.id, "22")
        XCTAssertEqual(np.queue.map(\.id), ["11", "22"])
        XCTAssertEqual(np.index, 1)
    }

    /// With no service connected there's nothing to route through, so it says so rather
    /// than playing something else.
    func test_spotifyWithNoRouterReportsRatherThanSubstituting() {
        let np = NowPlayingController()
        np.router = nil

        np.play(tracks: [spotifyTrack("s1", "Spotify One")], startAt: 0)

        XCTAssertEqual(np.current?.id, "s1")
        XCTAssertNotNil(np.playbackError, "Silence needs an explanation")
    }
}
