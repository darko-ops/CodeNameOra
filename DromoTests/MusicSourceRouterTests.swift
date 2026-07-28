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
        var library: [Track] = []
        /// Set to fail this source's fetch, to prove one bad service can't empty the rest.
        var fetchFails = false
        init(_ name: String, library: [Track] = []) {
            self.name = name
            self.library = library
        }

        struct Failure: Error {}

        /// Set false to stand in for a permission the runner revoked in iOS Settings.
        var isAuthorized = true
        private(set) var authorizationAsks = 0

        func requestAuthorization() async -> Bool {
            authorizationAsks += 1
            return isAuthorized
        }
        func fetchLibraryTracks() async throws -> [Track] {
            if fetchFails { throw Failure() }
            return library
        }
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

    // MARK: - Unified fetch

    func testFetchFoldsEverySourceIntoOneDedupedLibrary() async throws {
        // The same recording in both services, plus one unique to each.
        let shared = { (id: String, bpm: Double) in
            Track(id: id, title: "Shared Song", artist: "Artist", bpm: bpm,
                  energyLevel: 0.5, durationSeconds: 200, provider: .appleMusic)
        }
        let apple = StubProvider("apple", library: [shared("a1", 0), track("a2", provider: .appleMusic)])
        let spotify = StubProvider("spotify", library: [shared("s1", 168), track("s2", provider: .spotify)])
        let router = MusicSourceRouter(sources: [
            (kind: .appleMusic, provider: apple, tracks: []),
            (kind: .spotify, provider: spotify, tracks: []),
        ])

        let library = try await router.fetchLibraryTracks()

        XCTAssertEqual(library.count, 3, "the duplicate collapses — a runner sees one copy")
        XCTAssertEqual(library.filter { $0.title == "Shared Song" }.count, 1)
        XCTAssertEqual(library.first { $0.title == "Shared Song" }?.bpm, 168,
                       "the copy that knows its tempo is the one worth keeping")
    }

    func testFetchOrderFollowsConnectionOrderNotDictionaryOrder() async throws {
        // Dictionary iteration order is unspecified, so an order-dependent merge could
        // otherwise differ between launches. Repeat to catch a nondeterministic result.
        for _ in 0..<20 {
            let apple = StubProvider("apple", library: [track("a1", provider: .appleMusic)])
            let spotify = StubProvider("spotify", library: [track("s1", provider: .spotify)])
            let router = MusicSourceRouter(sources: [
                (kind: .appleMusic, provider: apple, tracks: []),
                (kind: .spotify, provider: spotify, tracks: []),
            ])
            let ids = try await router.fetchLibraryTracks().map(\.id)
            XCTAssertEqual(ids, ["a1", "s1"], "first-connected source comes first, every time")
        }
    }

    func testOneFailingSourceDoesNotEmptyTheLibrary() async throws {
        let apple = StubProvider("apple", library: [track("a1", provider: .appleMusic)])
        let spotify = StubProvider("spotify", library: [track("s1", provider: .spotify)])
        spotify.fetchFails = true
        let router = MusicSourceRouter(sources: [
            (kind: .appleMusic, provider: apple, tracks: []),
            (kind: .spotify, provider: spotify, tracks: []),
        ])

        let library = try await router.fetchLibraryTracks()
        XCTAssertEqual(library.map(\.id), ["a1"], "the healthy source still contributes")
    }

    // MARK: - Authorization

    func testAuthorizedWhileAnySourceStillIs() async {
        let apple = StubProvider("apple"), spotify = StubProvider("spotify")
        apple.isAuthorized = false            // revoked in iOS Settings
        let router = MusicSourceRouter(sources: [
            (kind: .appleMusic, provider: apple, tracks: []),
            (kind: .spotify, provider: spotify, tracks: []),
        ])

        let authorized = await router.requestAuthorization()

        XCTAssertTrue(authorized, "one working source is enough to run")
        XCTAssertEqual(apple.authorizationAsks, 1, "every source gets its chance to re-auth")
        XCTAssertEqual(spotify.authorizationAsks, 1)
    }

    func testNotAuthorizedWhenEverySourceHasBeenRevoked() async {
        // The case the old blanket `true` hid: nothing can play, and the app should
        // learn that here rather than from a mysteriously empty library.
        let apple = StubProvider("apple"), spotify = StubProvider("spotify")
        apple.isAuthorized = false
        spotify.isAuthorized = false
        let router = MusicSourceRouter(sources: [
            (kind: .appleMusic, provider: apple, tracks: []),
            (kind: .spotify, provider: spotify, tracks: []),
        ])

        let authorized = await router.requestAuthorization()
        XCTAssertFalse(authorized)
    }
}
