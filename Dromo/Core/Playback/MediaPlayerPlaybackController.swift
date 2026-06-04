import Foundation
import MediaPlayer
import os
import DromoCore

private let playbackLog = Logger(subsystem: "com.daed.dromo", category: "playback")
private func plog(_ m: String) { playbackLog.notice("\(m, privacy: .public)"); print("🎵 [playback] \(m)") }

/// `PlaybackControlling` backed by the system music player (Apple Music / MediaPlayer).
/// Plays by `MPMediaItem` persistent id — the same handle `AppleMusicProvider` uses.
/// When the current track finishes, it calls `onAdvance` so the live loop picks the
/// next selection (boundary-aligned switching, never a manual tap during a run).
///
/// Note: full-track Apple Music playback needs an Apple Music subscription/entitlement
/// (surfaced in onboarding). On the Simulator / without a match, `play` returns false
/// and the loop gracefully skips.
@MainActor
final class MediaPlayerPlaybackController: NSObject, PlaybackControlling {

    private let player = MPMusicPlayerController.applicationMusicPlayer

    /// Invoked when the now-playing item ends (single-item queue → nil).
    var onAdvance: (@Sendable () async -> Void)?

    override init() {
        super.init()
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(
            self, selector: #selector(nowPlayingItemChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
    }

    deinit { player.endGeneratingPlaybackNotifications() }

    nonisolated func play(trackID: String) async -> Bool {
        guard let persistentID = UInt64(trackID) else {
            plog("'\(trackID)' is not a library id (catalog/unplayable) → skip")
            return false
        }
        return await MainActor.run {
            let predicate = MPMediaPropertyPredicate(
                value: persistentID, forProperty: MPMediaItemPropertyPersistentID)
            let query = MPMediaQuery(filterPredicates: [predicate])
            let count = query.items?.count ?? 0
            guard count > 0 else {
                plog("no library item for id \(trackID) (count=0) → skip")
                return false
            }
            player.setQueue(with: query)
            player.play()
            plog("▶️ queued + play id \(trackID) (\(count) item, state=\(player.playbackState.rawValue))")
            return true
        }
    }

    @objc private func nowPlayingItemChanged() {
        if player.nowPlayingItem == nil, let onAdvance {
            Task { await onAdvance() }
        }
    }
}
