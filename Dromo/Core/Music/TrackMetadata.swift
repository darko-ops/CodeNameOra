import Foundation

/// Provider-specific raw metadata, unified into DromoCore.Track downstream (Section 6).
/// Phase 0 stub.
struct TrackMetadata {
    let id: String
    let title: String
    let artist: String
    let bpm: Double?
}
