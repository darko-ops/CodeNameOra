import Foundation
import DromoCore

/// Smooth track transitions (Section 5.3), conforming to DromoCore.TrackTransitioning
/// so the package's `MusicSequencer` can drive it.
///
/// Crossfading requires Dromo to own the audio: it resolves a `Track` to a local
/// file via `urlProvider` and equal-power crossfades through `AudioEngine`. With
/// streaming providers (Spotify / Apple Music) there is no local file — those
/// apps manage playback — so `urlProvider` returns nil and this no-ops, while the
/// provider's own `play(track:)` handles the switch.
final class CrossfadeController: TrackTransitioning {

    private let audio: AudioEngine
    private let duration: TimeInterval
    private let urlProvider: (Track) -> URL?

    init(audio: AudioEngine = AudioEngine(),
         duration: TimeInterval = 4.0,
         urlProvider: @escaping (Track) -> URL? = { _ in nil }) {
        self.audio = audio
        self.duration = duration
        self.urlProvider = urlProvider
    }

    func crossfade(to track: Track) async {
        guard let url = urlProvider(track) else { return }
        audio.crossfade(toFileAt: url, duration: duration)
    }
}
