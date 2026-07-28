import XCTest
import DromoCore
@testable import Dromo

/// The router resolves a track to the service that can actually play it. Its failure
/// mode is silence — `play` returns without throwing and nothing happens — so the
/// resolution rules are worth pinning even though they look obvious.
final class MusicSourceRouterTests: XCTestCase {

    /// Records what it was asked to play; stands in for a real service.
    private final class StubProvider: MusicProviderProtocol, @unchecked Sendable {
        let name: String
        private(set) var played: [String] = []
        init(_ name: String) { self.name = name }

        func requestAuthorization() async -> Bool { true }
        func fetchLibraryTracks() async throws -> [Track] { [] }
        func play(track: Track) async throws { played.append(track.id) }
    }

    private func track(_ id: String, provider: Track.MusicProvider) -> Track {
        Track(id: id, title: "Song \(id)", artist: "Artist", bpm: 170,
              energyLevel: 0.5, durationSeconds: 200, provider: provider)
    }

    func testPlaysThroughTheServiceThatOwnsTheTrack() async throws {
        let apple = StubProvider("apple"), spotify = StubProvider("spotify")
        let appleTrack = track("a1", provider: .appleMusic)
        let spotifyTrack = track("s1", provider: .spotify)
        let router = MusicSourceRouter(sources: [
            (kind: .appleMusic, provider: apple, tracks: [appleTrack]),
            (kind: .spotify, provider: spotify, tracks: [spotifyTrack]),
        ])

        try await router.play(track: appleTrack)
        try await router.play(track: spotifyTrack)

        XCTAssertEqual(apple.played, ["a1"])
        XCTAssertEqual(spotify.played, ["s1"])
    }

    /// The regression: a playlist entry naming a service the runner has toggled out of
    /// the mix. Resolving to that kind and stopping there returned nil and failed
    /// silently, even with another source able to play it.
    func testUnknownTrackNamingADisconnectedServiceStillPlays() async throws {
        let apple = StubProvider("apple")
        let router = MusicSourceRouter(sources: [
            (kind: .appleMusic, provider: apple, tracks: [track("a1", provider: .appleMusic)]),
        ])

        // Not in the mapping, and its own provider field points at absent Spotify.
        try await router.play(track: track("unknown", provider: .spotify))

        XCTAssertEqual(apple.played, ["unknown"],
                       "with one connected source there is no ambiguity — play it")
    }

    // NOTE: the router's "genuinely ambiguous" branch (unknown id, its named service
    // not connected, two or more sources) is unreachable while `Track.MusicProvider`
    // has exactly two cases — with both connected, every hint resolves. Left in the
    // router for when a third service arrives; untested until then rather than tested
    // against a contrived enum.
    func testTrackProviderFieldResolvesWhenTheMappingHasNotSeenTheID() async throws {
        let apple = StubProvider("apple"), spotify = StubProvider("spotify")
        let router = MusicSourceRouter(sources: [
            (kind: .appleMusic, provider: apple, tracks: []),
            (kind: .spotify, provider: spotify, tracks: []),
        ])

        // Added after the last library refresh, but it names a CONNECTED service.
        try await router.play(track: track("s9", provider: .spotify))

        XCTAssertEqual(spotify.played, ["s9"])
        XCTAssertTrue(apple.played.isEmpty)
    }
}
