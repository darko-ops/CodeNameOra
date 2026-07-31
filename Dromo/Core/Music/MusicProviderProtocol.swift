import Foundation
import DromoCore

/// Abstract interface over a music provider (Section 6).
protocol MusicProviderProtocol {
    func requestAuthorization() async -> Bool
    func fetchLibraryTracks() async throws -> [Track]
    func play(track: Track) async throws

    /// Whether this provider already holds a usable authorization, **without
    /// prompting**. Distinct from `requestAuthorization()`, which may present a
    /// sign-in flow — this is what lets a connection be restored silently at launch
    /// instead of asking the runner to sign in again every time.
    var isAuthorized: Bool { get async }

    /// A locally-readable (DRM-free) asset URL for a track, if one exists — the
    /// gate to on-device identity + analysis (Phase 0/3). Returns nil for DRM /
    /// cloud / streaming tracks (and for providers with no local files).
    func analyzableURL(forTrackID id: String) async -> URL?

    /// The recording's ISRC resolved via the provider's **catalog** API rather than
    /// the local file. The only identity path for DRM / cloud tracks (no assetURL,
    /// no file tag). Returns nil for providers without a catalog, or on no match.
    func catalogISRC(forTrackID id: String) async -> String?
}

extension MusicProviderProtocol {
    // Default: never pre-authorized, so a provider that hasn't opted in is simply not
    // restored rather than wrongly assumed connected.
    var isAuthorized: Bool { get async { false } }
    // Default: nothing analyzable (mock / streaming providers).
    func analyzableURL(forTrackID id: String) async -> URL? { nil }
    // Default: no catalog identity (mock / non-Apple providers).
    func catalogISRC(forTrackID id: String) async -> String? { nil }
}
