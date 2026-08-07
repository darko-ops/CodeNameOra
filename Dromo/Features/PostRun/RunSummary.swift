import Foundation
import DromoCore

/// The figures a finished run is described by, derived from what was recorded.
///
/// `PostRunSummaryView` used to read these off `SessionController`, which is why it
/// could only be shown after a `SessionController` run — a flow nothing reaches. They
/// belong to the recorded `Session` instead, which is what a live run actually produces
/// and what the history list already stores, so the same summary now serves both.
struct RunSummary {
    let session: Session

    var distanceMeters: Double { session.distanceMeters }
    var elapsedSeconds: Double { Double(session.elapsedSeconds) }
    var targetPaceSecondsPerKm: Double { session.targetPace }
    var samples: [PaceLog] { session.actualPaces }

    /// Average pace over the run.
    ///
    /// Taken from distance and time rather than by averaging the per-second pace
    /// samples: a mean of samples over-weights the slow ones, since standing still
    /// produces a huge pace figure for every second it lasts. Falls back to the sample
    /// mean when there is no distance — an indoor run with no GPS still has a pace.
    var averagePaceSecondsPerKm: Double {
        if distanceMeters > 0, elapsedSeconds > 0 {
            return elapsedSeconds / (distanceMeters / 1_000)
        }
        let paces = samples.map(\.paceSecondsPerKm).filter { $0 > 0 }
        guard !paces.isEmpty else { return 0 }
        return paces.reduce(0, +) / Double(paces.count)
    }

    /// How far off target the run ran, on average — the absolute gap, because two
    /// minutes fast and two minutes slow is not the same as being on pace.
    var averageGap: Double {
        let gaps = samples.map { abs($0.gapSeconds) }
        guard !gaps.isEmpty else { return 0 }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    /// Distinct tracks played. `tracks` holds one entry per play, so this is the count
    /// of times the music changed.
    var trackChanges: Int { session.tracks.count }

    /// The tempos that actually played, for the chart and the BPM range.
    var bpmHistory: [Double] {
        let fromSamples = samples.map(\.bpmPlaying).filter { $0 > 0 }
        guard fromSamples.isEmpty else { return fromSamples }
        // No per-second log (a short run, or one recorded without GPS) — fall back to
        // what each track's own tempo was.
        return session.tracks.map(\.track.bpm).filter { $0 > 0 }
    }

    /// "128–176", or nil when nothing that played carried a tempo.
    var bpmRangeText: String? {
        let bpms = bpmHistory
        guard let lo = bpms.min(), let hi = bpms.max() else { return nil }
        return lo == hi ? "\(Int(lo))" : "\(Int(lo))–\(Int(hi))"
    }
}
