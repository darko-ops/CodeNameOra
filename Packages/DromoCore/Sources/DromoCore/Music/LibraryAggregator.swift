import Foundation

/// Folds the libraries of every enabled music source into ONE library. The app used
/// to hold a single provider at a time, so connecting a second service replaced the
/// first; the product promise is the opposite — collect every connected library and
/// let the runner toggle sources in and out without losing any integration.
public enum LibraryAggregator {

    /// Merge per-source track lists in the order the sources were connected.
    ///
    /// Duplicate recordings — the same title + artist, case- and whitespace-folded,
    /// since `Track` carries no ISRC — collapse to one entry. A copy that knows its
    /// tempo always beats one that doesn't (tempo is what the engine paces on);
    /// otherwise the first-connected source keeps the track, so toggling a later
    /// source in never silently re-homes music the runner already sees.
    public static func merged(_ libraries: [[Track]]) -> [Track] {
        var indexByKey: [String: Int] = [:]
        var result: [Track] = []
        for library in libraries {
            for track in library {
                let key = dedupeKey(title: track.title, artist: track.artist)
                if let index = indexByKey[key] {
                    if result[index].bpm <= 0, track.bpm > 0 { result[index] = track }
                } else {
                    indexByKey[key] = result.count
                    result.append(track)
                }
            }
        }
        return result
    }

    /// Recording identity when no ISRC is known: lowercased, whitespace-normalized
    /// title|artist. Deliberately conservative — remix/live suffixes stay distinct.
    static func dedupeKey(title: String, artist: String) -> String {
        func fold(_ s: String) -> String {
            s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return fold(title) + "|" + fold(artist)
    }
}
