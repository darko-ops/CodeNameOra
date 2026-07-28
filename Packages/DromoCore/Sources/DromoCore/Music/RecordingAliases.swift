import Foundation

/// Maps every per-app track id to a stable RECORDING id, so anything the app learns
/// or looks up about a song attaches to the recording, not to whichever app's copy
/// happened to be playing.
///
/// The unified library dedupes copies visually; this is the data-layer half of the
/// same promise. Built over EVERY connected source's tracks — enabled or not — so
/// toggling a service out (or a different copy surviving the merge later) never
/// orphans what was learned through the other copy.
///
/// The recording id is derived from the same folded title|artist key the aggregator
/// dedupes by (upgradeable to ISRC in one place once `Track` carries it), which makes
/// it stable across launches, sources, and merge order.
public struct RecordingAliases: Sendable, Equatable {

    /// Namespaces recording ids away from platform track ids, so a stored key's kind
    /// is always recognizable.
    public static let prefix = "rec:"

    private let recordingByTrackID: [String: String]

    /// No aliases: every id resolves to itself. The identity behaves exactly like
    /// the pre-collective app, which is what makes the parameter safely optional.
    public init() {
        recordingByTrackID = [:]
    }

    public init(libraries: [[Track]]) {
        var map: [String: String] = [:]
        for library in libraries {
            for track in library {
                map[track.id] = Self.prefix
                    + LibraryAggregator.dedupeKey(title: track.title, artist: track.artist)
            }
        }
        recordingByTrackID = map
    }

    public var isEmpty: Bool { recordingByTrackID.isEmpty }

    /// The stable recording id for a track — the id itself when unknown, so callers
    /// never need a fallback branch.
    public func recordingID(for trackID: String) -> String {
        recordingByTrackID[trackID] ?? trackID
    }

    /// Re-key recording-level values to every current track id. Entries under keys
    /// this map doesn't know (legacy platform-keyed data written before collective
    /// learning) stay visible under their own key, so nothing already learned is lost.
    public func expanded<V>(_ byID: [String: V]) -> [String: V] {
        guard !recordingByTrackID.isEmpty else { return byID }
        var out = byID
        for (trackID, recordingID) in recordingByTrackID {
            if let value = byID[recordingID] { out[trackID] = value }
        }
        return out
    }
}
