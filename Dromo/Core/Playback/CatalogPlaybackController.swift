import Foundation
import AVFoundation
import os
import DromoCore

private let catalogLog = Logger(subsystem: "com.daed.dromo", category: "playback")
private func clog(_ m: String) { catalogLog.notice("\(m, privacy: .public)"); print("🎵 [catalog] \(m)") }

/// Plays the fallback catalog's bundled audio, and routes everything else to the
/// library player. One `PlaybackControlling` for the live loop, two sources beneath:
///
///   `catalog:170`  → bundled file via AVAudioPlayer   (Dromo's own mixes)
///   `1234567890`   → MPMusicPlayerController          (the runner's library)
///
/// The loop already drops whatever won't play, so an unstocked build degrades to
/// library-only automatically — no branch in the loop, no special case in selection.
@MainActor
final class CatalogPlaybackController: NSObject, PlaybackControlling, AVAudioPlayerDelegate {

    private let library: MediaPlayerPlaybackController
    private let catalog: CatalogLibrary
    private var player: AVAudioPlayer?

    /// Invoked when whichever source is playing reaches the end of a track.
    var onAdvance: (@Sendable () async -> Void)? {
        didSet { library.onAdvance = onAdvance }
    }

    init(library: MediaPlayerPlaybackController? = nil,
         catalog: CatalogLibrary = .shared) {
        // `MediaPlayerPlaybackController` is main-actor isolated, so it can't be a
        // default argument (those evaluate nonisolated) — build it here instead.
        self.library = library ?? MediaPlayerPlaybackController()
        self.catalog = catalog
        super.init()
    }

    nonisolated func play(trackID: String) async -> Bool {
        guard CatalogLibrary.isCatalogID(trackID) else {
            return await library.play(trackID: trackID)
        }
        return await MainActor.run { playCatalog(trackID) }
    }

    private func playCatalog(_ trackID: String) -> Bool {
        guard let url = catalog.url(forTrackID: trackID) else {
            clog("'\(trackID)' has no bundled audio (catalog not stocked) → skip")
            return false
        }
        do {
            // Duck nothing, own the session: the catalog IS the music here.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else {
                clog("AVAudioPlayer refused to start \(trackID)")
                return false
            }
            self.player?.stop()          // replace whatever was playing
            self.player = player
            clog("▶️ catalog \(trackID) (\(url.lastPathComponent))")
            return true
        } catch {
            clog("catalog playback failed for \(trackID): \(error.localizedDescription)")
            return false
        }
    }

    func pause() {
        player?.pause()
        library.pause()
    }

    func resume() {
        player?.play()
        library.resume()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    // Boundary-aligned switching: the finished catalog track hands control back to the
    // loop exactly the way a finished library track does.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            if let onAdvance { await onAdvance() }
        }
    }
}
