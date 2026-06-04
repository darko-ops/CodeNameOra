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

    // --- Candidate scoring weights ---
    /// Falloff (BPM) over which closeness-to-desired decays to 0.
    public var bpmTolerance: Double = 12
    public var bpmMatchWeight: Double = 1.0
    public var energyWeight: Double = 0.4
    public var beatStrengthWeight: Double = 0.5
    public var preferenceWeight: Double = 0.3

    /// Tracks below this BPM confidence are a last resort (score multiplied down).
    public var confidenceThreshold: Double = 0.5
    public var lowConfidencePenalty: Double = 0.5

    /// Don't repeat the last N selected tracks while alternatives exist.
    public var recentWindow: Int = 5

    public init() {}
}
