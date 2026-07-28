import Foundation

/// One line of "what moved you" — a track from this run and what the runner's body
/// actually did while it played.
///
/// The claim is deliberately narrow. Dromo measured a cadence change during a play
/// window; it did not prove the song caused it (hills, wind, and traffic lights don't
/// sign their work). So the copy says what was observed — "your cadence came up 6 spm
/// while this played" — and never "this song made you faster". Overclaiming here would
/// be the fastest way to lose a runner's trust in everything else the app says.
public struct RunHighlight: Sendable, Equatable {

    public let trackID: String
    public let mode: PaceMode
    /// Cadence gap closed while it played (spm). Positive = moved toward target.
    public let reward: Double
    /// Live samples behind the observation (~1 Hz, so ≈ seconds of play).
    public let samples: Int

    public init(trackID: String, mode: PaceMode, reward: Double, samples: Int) {
        self.trackID = trackID
        self.mode = mode
        self.reward = reward
        self.samples = samples
    }

    public var helped: Bool { reward > 0 }

    /// Plain language, in the unit that was actually measured. Cadence — not pace —
    /// because cadence is what the attributor observed; converting to s/km through the
    /// cadence model would multiply a 6 spm reading into a claim about minutes per
    /// kilometre that the measurement doesn't support.
    public var headline: String {
        let spm = abs(reward)
        let rounded = spm < 1 ? String(format: "%.1f", spm) : String(Int(spm.rounded()))
        switch (mode, helped) {
        case (.push, true):    return "Your cadence came up \(rounded) spm while this played"
        case (.push, false):   return "You drifted \(rounded) spm further behind"
        case (.settle, true):  return "You eased down \(rounded) spm — back toward target"
        case (.settle, false): return "You pushed \(rounded) spm further ahead"
        case (.hold, true):    return "You closed \(rounded) spm and held the groove"
        case (.hold, false):   return "Your cadence slipped \(rounded) spm off target"
        }
    }

    /// What the runner needed at the time — the context that makes the number mean
    /// something, since the same track can be right for a push and wrong for a settle.
    public var context: String {
        switch mode {
        case .push:   return "when you were behind pace"
        case .hold:   return "while you were on pace"
        case .settle: return "when you were ahead of pace"
        }
    }
}

/// Turns a run's finalized responses into the post-run "What moved you" section.
/// Pure — the app supplies the responses it already collects for learning, so the
/// summary and the learner can never tell different stories about the same run.
public enum RunHighlights {

    /// Ranked best-first. Short plays are dropped: a 20-second window is noise, and
    /// presenting it as a finding would teach the runner to distrust the section.
    public static func from(_ responses: [TrackResponse],
                            minSamples: Int = 30,
                            limit: Int = 3) -> [RunHighlight] {
        responses
            .filter { $0.samples >= minSamples }
            .map { RunHighlight(trackID: $0.trackID, mode: $0.mode,
                                reward: $0.reward, samples: $0.samples) }
            .sorted { $0.reward != $1.reward ? $0.reward > $1.reward : $0.trackID < $1.trackID }
            .prefix(limit)
            .map { $0 }
    }

    /// The one that cost the most, if any — shown only when it's a real drag, so the
    /// section doesn't nag about a track that was merely unremarkable.
    public static func drag(_ responses: [TrackResponse],
                            minSamples: Int = 30,
                            threshold: Double = 2) -> RunHighlight? {
        responses
            .filter { $0.samples >= minSamples && $0.reward <= -threshold }
            .min { $0.reward < $1.reward }
            .map { RunHighlight(trackID: $0.trackID, mode: $0.mode,
                                reward: $0.reward, samples: $0.samples) }
    }

    /// Nothing worth showing — a short run, or every play too brief to attribute. The
    /// caller should hide the section entirely rather than render an empty box.
    public static func isEmpty(_ responses: [TrackResponse], minSamples: Int = 30) -> Bool {
        from(responses, minSamples: minSamples).isEmpty
    }
}
