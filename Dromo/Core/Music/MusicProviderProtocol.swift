import Foundation
import DromoCore

/// Abstract interface over a music provider (Section 6).
protocol MusicProviderProtocol {
    func requestAuthorization() async -> Bool
    func fetchLibraryTracks() async throws -> [Track]
    func play(track: Track) async throws

    /// A locally-readable (DRM-free) asset URL for a track, if one exists — the
    /// gate to on-device identity + analysis (Phase 0/3). Returns nil for DRM /
    /// cloud / streaming tracks (and for providers with no local files).
    func analyzableURL(forTrackID id: String) async -> URL?
}

extension MusicProviderProtocol {
    // Default: nothing analyzable (mock / streaming providers).
    func analyzableURL(forTrackID id: String) async -> URL? { nil }
}
