import Foundation

/// All tunable knobs for the runtime selection engine — thresholds and weights live
/// here, never as magic numbers buried in the logic (Phase 4 requirement), so they
/// can be tuned against real runs without touching the engine.
public struct SelectionConfig: Sendable, Equatable {

    // --- Gap / nudge (steps-per-minute) ---
    /// |gap| within this is "on pace".
    public var onPaceTolerance: Double = 4
    /// Schmitt-trigger HIGH: |gap| must reach this to ENTER speed-up / slow-down.
    public var nudgeEnterThreshold: Double = 8
    /// Schmitt-trigger LOW: |gap| must fall to this to RETURN to hold. Below the
    /// enter threshold ⇒ hysteresis band that prevents nudge thrashing.
    public var nudgeExitThreshold: Double = 4

    // --- Desired BPM derivation ---
    /// spm gap → BPM offset applied to the target when picking the next track.
    public var bpmPushGain: Double = 0.6
    /// Clamp on that offset, so a huge gap can't demand an absurd tempo.
    public var maxBPMOffset: Double = 20

    // --- Candidate scoring ---
    /// Falloff (BPM) over which tempo-fit decays from 1 to 0. Wide enough that a
    /// good off-tempo track survives; narrow enough that wildly-wrong tempos die.
    /// BPM SHAPES the score — it never gates the candidate out.
    public var bpmTolerance: Double = 12

    /// Blend weights for the three sub-scores (tempo fit, energy, beat strength).
    /// Each sub-score is 0–1, so weights are directly comparable; each set ~sums to 1.
    public struct Weights: Sendable, Equatable {
        public var tempo: Double
        public var energy: Double
        public var beat: Double
        public init(tempo: Double, energy: Double, beat: Double) {
            self.tempo = tempo; self.energy = energy; self.beat = beat
        }
    }

    /// The weights SHIFT WITH INTENT — the thing that makes selection feel like a DJ
    /// rather than a metronome. Behind pace, energy outranks exact tempo (a driving
    /// off-tempo track wins the push); on pace, tempo + steady beat lock the groove;
    /// ahead, calmer tracks win. These specific numbers are deliberate GUESSES — they
    /// only get right by feel on real runs, and the learning loop will later tune them.
    public var pushWeights   = Weights(tempo: 0.30, energy: 0.50, beat: 0.20)  // behind → drive
    public var holdWeights   = Weights(tempo: 0.45, energy: 0.20, beat: 0.35)  // on pace → lock groove
    public var settleWeights = Weights(tempo: 0.40, energy: 0.25, beat: 0.35)  // ahead → settle

    /// Bonus weight for learned taste (the per-user preference signal).
    public var preferenceWeight: Double = 0.3

    /// Weight on the LEARNED behavioral signal — how well a track has actually moved
    /// this runner the right way in this mode before. The strongest predictor of
    /// "good to push to" (it beats audio features), so it's weighted high; but it's
    /// neutral (0.5) until earned, so it only bites once runs accumulate. Applied as
    /// ±this around neutral, so a proven track can override a better tempo match.
    public var effectivenessWeight: Double = 0.5

    /// Tracks below this BPM confidence are a last resort (merit multiplied down).
    public var confidenceThreshold: Double = 0.5
    public var lowConfidencePenalty: Double = 0.5

    /// Soft repeat penalty (NOT a hard exclusion): the most-recent pick is docked this
    /// much, decaying toward 0 across the window — so variety is the default, but a
    /// clearly-superior track can still win again. Behavior, not a gate.
    public var repeatPenalty: Double = 0.4
    /// How many recent picks the penalty spans.
    public var recentWindow: Int = 5

    public init() {}
}
