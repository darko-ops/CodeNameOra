import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import DromoCore

/// Standalone music player for browsing (separate from the live-run loop). Plays a
/// queue of tracks, tracks elapsed/duration for a scrubber, and supports skip forward /
/// back. Shared app-wide as an environment object so a mini-player + Now Playing screen
/// can drive it from anywhere.
///
/// Playback is routed by the track's own service. The system music player
/// (`MPMusicPlayerController`) can only queue items from the local media library, so a
/// Spotify track goes out through `MusicSourceRouter` to the Spotify provider instead —
/// the same routing the live-run loop already used. Browsing didn't, and because Spotify
/// ids aren't numeric they silently fell out of the queue while the tapped index stayed
/// put, so choosing a Spotify song played whichever Apple Music song slid into its place.
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
    /// How "up next" is ordered (replaces the old shuffle toggle). Persisted.
    @Published private(set) var queueOrder: QueueOrder = .inOrder
    @Published private(set) var repeatMode: RepeatMode = .off

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    /// Why the last play attempt didn't produce sound. Surfaced rather than swallowed:
    /// Spotify playback needs the Spotify app and an active device, and silence with no
    /// explanation is indistinguishable from a broken app.
    @Published var playbackError: String?

    /// Routes a track to whichever service owns it. Set by `RootView` from the
    /// coordinator; nil until a service is connected.
    var router: MusicProviderProtocol?

    /// Which engine is driving the current queue. The system player's clock is
    /// meaningless for a track it isn't playing.
    private enum Engine { case systemLibrary, external }
    private var engine: Engine = .systemLibrary

    private let player = MPMusicPlayerController.applicationMusicPlayer
    private var timer: Timer?
    /// The list as given to `play` (so order modes re-derive from the full set).
    private var originalOrder: [Track] = []
    /// Cached learned taste (likes/skips), for taste-aware ordering. Refreshed in the
    /// background so `play`/`setOrder` stay synchronous.
    private var preferences: [String: Double] = [:]
    private let preferenceStore = GRDBPreferenceStore()
    private let orderKey = "dromo.nowplaying.queueOrder"

    init() {
        if let raw = UserDefaults.standard.string(forKey: orderKey),
           let saved = QueueOrder(rawValue: raw) { queueOrder = saved }
        // Expanded through the current alias map: a like recorded through one app's
        // copy of a song weighs its duplicates in other apps too.
        Task { preferences = RecordingAliasesHolder.current.expanded(await preferenceStore.weights()) }
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
        let start = max(0, min(startIndex, tracks.count - 1))
        guard let chosen = tracks.indices.contains(start) ? tracks[start] : nil else { return }
        playbackError = nil

        // The queue is narrowed to the chosen track's own service. One system queue
        // can't hold both a library item and a Spotify stream, and mixing them is what
        // let the index drift onto the wrong song — so "up next" follows the service you
        // picked from rather than quietly skipping everything it can't play.
        let sameService = tracks.filter { $0.provider == chosen.provider }
        originalOrder = sameService

        if queueOrder == .inOrder {
            queue = sameService
            index = sameService.firstIndex { $0.id == chosen.id } ?? 0
        } else {
            queue = QueueOrganizer.organize(sameService, order: queueOrder, seed: chosen,
                                            preferences: preferences,
                                            shuffleSeed: UInt64.random(in: .min ... .max))
            index = queue.firstIndex { $0.id == chosen.id } ?? 0
        }

        if playsThroughSystemLibrary(chosen) {
            startSystemLibraryPlayback()
        } else {
            startExternalPlayback(chosen)
        }

        duration = Double(current?.durationSeconds ?? 0)
        elapsed = 0
        artwork = currentArtworkImage()
        isExpanded = true
        startTimer()
        updateNowPlayingInfo()
        Task {   // refresh taste for next time, expanded across duplicate copies
            preferences = RecordingAliasesHolder.current.expanded(await preferenceStore.weights())
        }
    }

    /// Only tracks the local media library can actually resolve go to the system player.
    /// Media-library ids are numeric `persistentID`s; Spotify's are base-62 strings, so
    /// the id itself is the discriminator, with the provider as the intent.
    ///
    /// Internal rather than private so the routing decision — the thing that was wrong —
    /// can be asserted without a device that has both services installed.
    func playsThroughSystemLibrary(_ track: Track) -> Bool {
        track.provider == .appleMusic && UInt64(track.id) != nil
    }

    private func startSystemLibraryPlayback() {
        engine = .systemLibrary
        let items = mediaItems(for: queue)
        // Index against the resolved items by id rather than by position: an unresolvable
        // track shifts everything after it, which is precisely the drift that played the
        // wrong song.
        guard let chosen = current,
              let itemIndex = items.firstIndex(where: { String($0.persistentID) == chosen.id })
        else {
            playbackError = "That song isn't available in your library on this device."
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.shuffleMode = .off                // we own the shuffle order
        player.setQueue(with: MPMediaItemCollection(items: items))
        player.nowPlayingItem = items[itemIndex]
        player.play()
    }

    /// Hands the track to the service that owns it (today: Spotify, via App Remote or
    /// the Web API). Advancing the queue is driven here rather than by the system
    /// player, which isn't involved.
    private func startExternalPlayback(_ track: Track) {
        engine = .external
        player.stop()
        guard let router else {
            playbackError = "Connect \(track.provider.displayName) to play this song."
            return
        }
        isPlaying = true
        Task {
            do {
                try await router.play(track: track)
            } catch {
                isPlaying = false
                // The provider's own message says what to do about it (no active
                // device, not Premium, not signed in); a generic one would throw that
                // away and leave the runner guessing.
                playbackError = error.localizedDescription
            }
        }
    }

    func togglePlayPause() {
        guard engine == .systemLibrary else {
            // The external service owns transport; reflect intent and let the next
            // play() call re-assert it rather than pretending to pause someone else.
            isPlaying.toggle()
            return
        }
        player.playbackState == .playing ? player.pause() : player.play()
    }

    func next() {
        guard engine == .systemLibrary else {
            advanceExternal(by: 1)
            return
        }
        player.skipToNextItem()
    }

    /// Jump to a specific position in the current queue (tapped from Up Next).
    func jump(to queueIndex: Int) {
        guard queue.indices.contains(queueIndex) else { return }
        play(tracks: queue, startAt: queueIndex)
    }

    /// Change how "up next" is ordered, re-deriving from the full list with the current
    /// track pinned first (playback continues uninterrupted). Persisted across launches.
    func setOrder(_ order: QueueOrder) {
        queueOrder = order
        UserDefaults.standard.set(order.rawValue, forKey: orderKey)
        guard let current else { return }   // nothing playing — applies on next play()
        let position = player.currentPlaybackTime

        if order == .inOrder {
            let idx = originalOrder.firstIndex { $0.id == current.id } ?? 0
            requeue(originalOrder, startAt: idx, resumeAt: position)
        } else {
            let reordered = QueueOrganizer.organize(originalOrder, order: order, seed: current,
                                                    preferences: preferences,
                                                    shuffleSeed: UInt64.random(in: .min ... .max))
            requeue(reordered, startAt: 0, resumeAt: position)
        }
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
        guard engine == .systemLibrary else {
            advanceExternal(by: -1)
            return
        }
        if player.currentPlaybackTime > 3 { player.skipToBeginning() }   // restart, then prev
        else { player.skipToPreviousItem() }
    }

    /// Step the queue ourselves when the audio is coming from another app.
    private func advanceExternal(by offset: Int) {
        let next = index + offset
        guard queue.indices.contains(next) else { return }
        play(tracks: queue, startAt: next)
    }

    func seek(to seconds: Double) {
        guard engine == .systemLibrary else { return }   // no scrub handle on a remote app
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
        // The system player's clock describes whatever IT is playing. While another
        // service holds the audio that's a different song, so reading it would show a
        // scrubber advancing through the wrong track.
        guard engine == .systemLibrary else { return }
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
