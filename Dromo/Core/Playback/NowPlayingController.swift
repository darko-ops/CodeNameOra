import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import DromoCore

/// Standalone music player for browsing (separate from the live-run loop). Plays a
/// queue of tracks via the system music player, tracks elapsed/duration for a
/// scrubber, and supports skip forward / back. Shared app-wide as an environment
/// object so a mini-player + Now Playing screen can drive it from anywhere.
@MainActor
final class NowPlayingController: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    /// Drives the full-screen Now Playing presentation.
    @Published var isExpanded = false
    /// Real album art for the current item (nil → fall back to generated art).
    @Published private(set) var artwork: UIImage?

    enum RepeatMode { case off, all, one }
    @Published private(set) var isShuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    private let player = MPMusicPlayerController.applicationMusicPlayer
    private var timer: Timer?
    /// The un-shuffled order, so shuffle can be turned back off.
    private var originalOrder: [Track] = []

    init() {
        player.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(itemChanged),
                       name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
        nc.addObserver(self, selector: #selector(stateChanged),
                       name: .MPMusicPlayerControllerPlaybackStateDidChange, object: player)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        setupRemoteCommands()   // Lock Screen / Control Center / headphone controls
    }

    deinit { player.endGeneratingPlaybackNotifications() }

    /// Play `tracks` as a queue, starting at `startAt`, and present Now Playing. When
    /// shuffle is on, the queue order itself is shuffled (so Up Next matches playback).
    func play(tracks: [Track], startAt startIndex: Int) {
        originalOrder = tracks
        let start = max(0, min(startIndex, tracks.count - 1))
        let order = isShuffle ? shuffledOrder(tracks, firstIndex: start) : tracks
        queue = order
        index = isShuffle ? 0 : start
        let items = mediaItems(for: order)
        guard !items.isEmpty else { return }   // mock/Spotify ids aren't library items
        try? AVAudioSession.sharedInstance().setActive(true)
        player.shuffleMode = .off                // we own the shuffle order
        player.setQueue(with: MPMediaItemCollection(items: items))
        player.nowPlayingItem = items.indices.contains(index) ? items[index] : items.first
        player.play()
        duration = Double(current?.durationSeconds ?? 0)
        elapsed = 0
        artwork = currentArtworkImage()
        isExpanded = true
        startTimer()
        updateNowPlayingInfo()
    }

    private func shuffledOrder(_ tracks: [Track], firstIndex: Int) -> [Track] {
        guard tracks.indices.contains(firstIndex) else { return tracks.shuffled() }
        let first = tracks[firstIndex]
        let rest = tracks.enumerated().filter { $0.offset != firstIndex }.map(\.element).shuffled()
        return [first] + rest
    }

    func togglePlayPause() {
        player.playbackState == .playing ? player.pause() : player.play()
    }

    func next() { player.skipToNextItem() }

    /// Jump to a specific position in the current queue (tapped from Up Next).
    func jump(to queueIndex: Int) {
        guard queue.indices.contains(queueIndex) else { return }
        play(tracks: queue, startAt: queueIndex)
    }

    func toggleShuffle() {
        isShuffle.toggle()
        guard let current else { return }   // nothing playing — state recorded for next play()

        let newOrder: [Track]
        let newIndex: Int
        if isShuffle {
            newOrder = [current] + queue.filter { $0.id != current.id }.shuffled()
            newIndex = 0
        } else {
            newOrder = originalOrder
            newIndex = originalOrder.firstIndex { $0.id == current.id } ?? 0
        }
        requeue(newOrder, startAt: newIndex, resumeAt: player.currentPlaybackTime)
    }

    /// Re-set the playback queue (e.g. after toggling shuffle) and resume the current
    /// song where it was, so reordering doesn't interrupt playback.
    private func requeue(_ tracks: [Track], startAt newIndex: Int, resumeAt position: Double) {
        queue = tracks
        index = max(0, min(newIndex, tracks.count - 1))
        let items = mediaItems(for: tracks)
        guard !items.isEmpty else { return }
        player.shuffleMode = .off
        player.setQueue(with: MPMediaItemCollection(items: items))
        player.nowPlayingItem = items.indices.contains(index) ? items[index] : items.first
        player.play()
        player.currentPlaybackTime = position
        elapsed = position
        updateNowPlayingInfo()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off:  repeatMode = .all; player.repeatMode = .all
        case .all:  repeatMode = .one; player.repeatMode = .one
        case .one:  repeatMode = .off; player.repeatMode = .none
        }
    }

    func previous() {
        if player.currentPlaybackTime > 3 { player.skipToBeginning() }   // restart, then prev
        else { player.skipToPreviousItem() }
    }

    func seek(to seconds: Double) {
        player.currentPlaybackTime = seconds
        elapsed = seconds
    }

    // MARK: - Internals

    private func mediaItems(for tracks: [Track]) -> [MPMediaItem] {
        let ids = tracks.compactMap { UInt64($0.id) }
        guard !ids.isEmpty else { return [] }
        let all = MPMediaQuery.songs().items ?? []
        let byID = Dictionary(all.map { ($0.persistentID, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        elapsed = player.currentPlaybackTime
        if duration <= 0 { duration = player.nowPlayingItem?.playbackDuration ?? 0 }
        isPlaying = player.playbackState == .playing
        updateNowPlayingInfo()
    }

    @objc private func itemChanged() {
        isPlaying = player.playbackState == .playing
        duration = player.nowPlayingItem?.playbackDuration ?? Double(current?.durationSeconds ?? 0)
        elapsed = 0
        if let pid = player.nowPlayingItem?.persistentID,
           let i = queue.firstIndex(where: { UInt64($0.id) == pid }) {
            index = i
        }
        artwork = currentArtworkImage()
        updateNowPlayingInfo()
    }

    private func currentArtworkImage() -> UIImage? {
        player.nowPlayingItem?.artwork?.image(at: CGSize(width: 600, height: 600))
    }

    @objc private func stateChanged() {
        isPlaying = player.playbackState == .playing
        updateNowPlayingInfo()
    }

    // MARK: - Lock Screen / Now Playing

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.play() }; return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause() }; return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }; return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }; return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }; return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: e.positionTime) }
            }
            return .success
        }
    }

    /// Publish current track + timing + album art to the Lock Screen / Control Center.
    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = current else { center.nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        // Real album art for the library item (nil for tracks without artwork).
        if let artwork = player.nowPlayingItem?.artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        center.nowPlayingInfo = info
    }
}
