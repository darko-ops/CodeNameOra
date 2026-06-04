import Foundation
import DromoCore

/// Demo stand-in for the real Spotify integration. It conforms to the same
/// `MusicProviderProtocol` the production `SpotifyProvider` will, so the UI and
/// session loop are written against the protocol, not the mock. Swapping in the
/// real SDK (Section 6.2) requires no view changes.
final class MockSpotifyProvider: MusicProviderProtocol {

    /// Simulates the OAuth round-trip (real flow bounces out to the Spotify app).
    func requestAuthorization() async -> Bool {
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        return true
    }

    func fetchLibraryTracks() async throws -> [Track] {
        try? await Task.sleep(nanoseconds: 400_000_000)
        return MockMusicCatalog.tracks
    }

    func play(track: Track) async throws {
        // No-op in the demo; real playback goes through SPTAppRemote.
    }
}
