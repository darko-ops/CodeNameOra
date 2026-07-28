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
        let recordings = recordingIDs(libraries)
        var indexByRecording: [String: Int] = [:]
        var result: [Track] = []
        for library in libraries {
            for track in library {
                let recording = recordings[track.id] ?? track.id
                if let index = indexByRecording[recording] {
                    if result[index].bpm <= 0, track.bpm > 0 { result[index] = track }
                } else {
                    indexByRecording[recording] = result.count
                    result.append(track)
                }
            }
        }
        return result
    }

    /// Two recordings can share a title and an artist and still be different tracks —
    /// a studio cut and a live one, most often, and their tempos differ by more than
    /// the engine's tolerance. Runtimes are what separate them: cross-service copies
    /// of the same recording agree within a second or two, while a live version runs
    /// minutes longer.
    ///
    /// Anything closer than this counts as the same recording.
    static let sameRecordingToleranceSeconds = 20

    /// Every track id → the id of the RECORDING it belongs to.
    ///
    /// Tracks sharing a folded title|artist are grouped by runtime proximity. The
    /// common case — one recording, however many copies — keeps the bare
    /// `title|artist` key, so ids already carrying learned data never move. Only a
    /// genuine second recording gets a suffix, and it's the longer one that takes it.
    ///
    /// Sorted by duration rather than by connection order, so the same library yields
    /// the same ids no matter which service the runner connected first.
    static func recordingIDs(_ libraries: [[Track]]) -> [String: String] {
        var byKey: [String: [Track]] = [:]
        for library in libraries {
            for track in library {
                byKey[dedupeKey(title: track.title, artist: track.artist), default: []]
                    .append(track)
            }
        }

        var out: [String: String] = [:]
        for (key, tracks) in byKey {
            // Unknown runtimes (0) can't separate anything — group them with the rest
            // rather than splitting a recording on missing metadata.
            let sorted = tracks.sorted {
                $0.durationSeconds != $1.durationSeconds
                    ? $0.durationSeconds < $1.durationSeconds
                    : $0.id < $1.id
            }
            var groupIndex = 0
            var anchor: Int?
            for track in sorted {
                if let current = anchor, track.durationSeconds > 0, current > 0,
                   track.durationSeconds - current > sameRecordingToleranceSeconds {
                    groupIndex += 1                    // a genuinely different recording
                    anchor = track.durationSeconds
                } else if anchor == nil || anchor == 0 {
                    anchor = track.durationSeconds     // first known runtime anchors the group
                }
                out[track.id] = groupIndex == 0 ? key : "\(key)|alt\(groupIndex)"
            }
        }
        return out
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
