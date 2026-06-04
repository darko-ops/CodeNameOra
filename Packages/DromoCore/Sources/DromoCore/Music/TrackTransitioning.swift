import Foundation

/// Abstraction over the audio crossfade engine (Section 5.3 / CrossfadeController).
///
/// The concrete AVFoundation implementation lives in the app target; the
/// sequencer and its tests depend only on this protocol.
public protocol TrackTransitioning: AnyObject {
    /// Crossfades playback to `track`.
    func crossfade(to track: Track) async
}
