import Foundation
import DromoCore

/// Real Spotify integration (Section 6.2), behind the shared `MusicProviderProtocol`.
///
/// - Auth: Authorization Code + PKCE via `SpotifyAuthService` (system frameworks).
/// - Library + BPM: `SpotifyWebAPI` (`/me/tracks` + `/audio-features`).
/// - Playback: Spotify App Remote when `SpotifyiOS.xcframework` is present;
///   otherwise the Web API `/me/player/play` fallback (Premium + active device).
final class SpotifyProvider: MusicProviderProtocol {

    let auth: SpotifyAuthService
    private let api: SpotifyWebAPI

    @MainActor
    init() {
        let auth = SpotifyAuthService()
        self.auth = auth
        self.api = SpotifyWebAPI(auth: auth)
    }

    func requestAuthorization() async -> Bool {
        do {
            try await auth.authorize()
            return true
        } catch {
            return false
        }
    }

    func fetchLibraryTracks() async throws -> [Track] {
        try await api.savedTracks()
    }

    /// True if the last library fetch couldn't read tempo (Spotify BPM restricted).
    func bpmUnavailable() async -> Bool {
        await api.lastAudioFeaturesForbidden
    }

    func play(track: Track) async throws {
        #if canImport(SpotifyiOS)
        let token = try await auth.validAccessToken()
        await playViaAppRemote(trackID: track.id, token: token)
        #else
        try await api.play(trackID: track.id)
        #endif
    }

    #if canImport(SpotifyiOS)
    private var appRemote: SpotifyAppRemoteController?

    @MainActor
    private func playViaAppRemote(trackID: String, token: String) {
        let controller = appRemote ?? SpotifyAppRemoteController(accessToken: token)
        appRemote = controller            // retain across calls
        controller.play(trackID: trackID)
    }
    #endif
}
