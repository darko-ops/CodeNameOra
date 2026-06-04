import Foundation
import MediaPlayer
import DromoCore

/// Apple Music integration (Section 6.1) behind the shared `MusicProviderProtocol`.
///
/// BPM is read from `MPMediaItem.beatsPerMinute` via the MediaPlayer framework —
/// the one mainstream source still exposing tempo (unlike Spotify's now-restricted
/// audio-features endpoint, see [[spotify-bpm-restriction]]). No binary SDK needed.
///
/// Caveat: `beatsPerMinute` is only populated for tracks whose metadata carries
/// it; coverage varies by library, so tracks without a BPM are dropped.
/// `lastLibraryHadNoBPM` lets the UI explain a thin/empty result.
final class AppleMusicProvider: MusicProviderProtocol {

    private let player = MPMusicPlayerController.applicationMusicPlayer
    /// Library had songs, but none carried a BPM tag.
    private(set) var lastLibraryHadNoBPM = false
    /// No songs at all (e.g. the Simulator, which has no Music library).
    private(set) var lastLibraryWasEmpty = false

    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized
    }

    func fetchLibraryTracks() async throws -> [Track] {
        let items = MPMediaQuery.songs().items ?? []
        // Return the WHOLE library for browsing. BPM comes from the `beatsPerMinute`
        // tag when present, else 0 ("unknown") — it's filled later by on-device
        // analysis / the Global Track Table, NOT required just to show your songs.
        let tracks = items.compactMap { item -> Track? in
            guard let title = item.title else { return nil }
            return Track(
                id: String(item.persistentID),
                title: title,
                artist: item.artist ?? "Unknown",
                bpm: Double(item.beatsPerMinute),   // 0 when untagged
                energyLevel: 0.5,
                durationSeconds: Int(item.playbackDuration),
                provider: .appleMusic
            )
        }
        lastLibraryWasEmpty = items.isEmpty
        lastLibraryHadNoBPM = !items.isEmpty && tracks.allSatisfy { $0.bpm <= 0 }
        return tracks
    }

    func play(track: Track) async throws {
        guard let persistentID = UInt64(track.id) else { return }
        let predicate = MPMediaPropertyPredicate(
            value: persistentID,
            forProperty: MPMediaItemPropertyPersistentID
        )
        player.setQueue(with: MPMediaQuery(filterPredicates: [predicate]))
        player.play()
    }

    /// The on-device asset URL for a library item. Non-nil only for DRM-free items
    /// (owned/purchased/synced); nil for Apple Music cloud/downloaded tracks
    /// (Phase 0 boundary) — those resolve via ISRC lookup or the catalog instead.
    func analyzableURL(forTrackID id: String) async -> URL? {
        guard let persistentID = UInt64(id) else { return nil }
        let predicate = MPMediaPropertyPredicate(
            value: persistentID, forProperty: MPMediaItemPropertyPersistentID)
        return MPMediaQuery(filterPredicates: [predicate]).items?.first?.assetURL
    }
}
