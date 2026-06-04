import Foundation

/// The heart of Dromo (Phase 4). Maps (target cadence, live cadence, candidate facts)
/// → next track + a SPEED_UP / HOLD / SLOW_DOWN nudge.
///
/// Speed-up vs slow-down is a **runtime function of the runner's state**, never a
/// property of a song (ARCHITECTURE central principle). Songs supply only objective
/// ingredients (`TrackFacts`: bpm, octave flag, energy, beat_strength, confidence);
/// the engine supplies the recipe. It reads no sensors — cadence is injected (Phase 5).
///
/// It carries runtime state (current nudge for hysteresis, recently-played ids), but
/// that is *session* state, not per-song state. Given the same sequence of inputs it
/// produces the same outputs — deterministic and unit-testable.
public struct SelectionEngine {

    public enum Nudge: String, Sendable, Equatable {
        case speedUp, hold, slowDown
    }

    public struct Decision: Sendable, Equatable {
        public let trackID: String
        public let effectiveBPM: Double   // the octave interpretation used for pacing
        public let nudge: Nudge
    }

    private struct Scored { let facts: TrackFacts; let score: Double }

    public var config: SelectionConfig
    private var currentNudge: Nudge = .hold
    private var recent: [String] = []

    public init(config: SelectionConfig = .init()) {
        self.config = config
    }

    // MARK: - Public API

    /// Update only the nudge (HUD signal) from the current cadence gap, applying
    /// hysteresis. Exposed so Phase 5 can refresh the HUD between track changes.
    @discardableResult
    public mutating func updateNudge(targetCadence: Double, currentCadence: Double) -> Nudge {
        applyHysteresis(gap: targetCadence - currentCadence)
    }

    /// Pick the next track for the current state and advance runtime state. Returns
    /// nil only when the candidate pool is empty.
    public mutating func selectNext(
        targetCadence: Double,
        currentCadence: Double,
        candidates: [TrackFacts],
        preferences: [String: Double] = [:]
    ) -> Decision? {
        guard !candidates.isEmpty else { return nil }

        let gap = targetCadence - currentCadence
        let nudge = applyHysteresis(gap: gap)
        let desired = desiredBPM(targetCadence: targetCadence, gap: gap)

        // Repeat-avoidance: skip recently played while alternatives remain.
        var pool = candidates.filter { !recent.contains($0.id) }
        if pool.isEmpty { pool = candidates }

        // Deterministic ranking: score desc, then id asc to break ties.
        var scored: [Scored] = []
        for f in pool {
            let s = score(f, desired: desired, target: targetCadence,
                          gap: gap, preference: preferences[f.id] ?? 0)
            scored.append(Scored(facts: f, score: s))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.facts.id < $1.facts.id }

        guard let best = scored.first else { return nil }

        recent.append(best.facts.id)
        if recent.count > config.recentWindow { recent.removeFirst() }

        return Decision(trackID: best.facts.id,
                        effectiveBPM: effectiveBPM(best.facts, targetCadence: targetCadence),
                        nudge: nudge)
    }

    // MARK: - Octave resolution (the 85-vs-170 problem)

    /// Resolve a candidate's tempo octave against the runner's cadence: of the
    /// plausible interpretations the flag allows, pick the one closest to target.
    public func effectiveBPM(_ facts: TrackFacts, targetCadence: Double) -> Double {
        var options = [facts.bpm]
        switch facts.tempoOctaveFlag {
        case .half:      options.append(facts.bpm / 2)            // true tempo may be half
        case .double:    options.append(facts.bpm * 2)            // …or double
        case .ambiguous: options.append(contentsOf: [facts.bpm / 2, facts.bpm * 2])
        case .none:      break
        }
        return options.min { abs($0 - targetCadence) < abs($1 - targetCadence) } ?? facts.bpm
    }

    // MARK: - Private

    private func desiredBPM(targetCadence: Double, gap: Double) -> Double {
        let offset = max(-config.maxBPMOffset, min(config.maxBPMOffset, gap * config.bpmPushGain))
        return targetCadence + offset   // behind (gap>0) ⇒ push tempo up; ahead ⇒ down
    }

    private func score(_ f: TrackFacts, desired: Double, target: Double,
                       gap: Double, preference: Double) -> Double {
        let eff = effectiveBPM(f, targetCadence: target)
        let closeness = max(0, 1 - abs(eff - desired) / config.bpmTolerance)

        // Directional energy: behind → favor high energy/drive, ahead → calmer,
        // on pace → favor moderate.
        let energy = f.energy ?? 0.5
        let directionalEnergy: Double
        if gap > config.onPaceTolerance { directionalEnergy = energy }
        else if gap < -config.onPaceTolerance { directionalEnergy = 1 - energy }
        else { directionalEnergy = 1 - abs(energy - 0.5) * 2 }

        let beat = f.beatStrength ?? 0.5

        let closenessTerm = config.bpmMatchWeight * closeness
        let energyTerm = config.energyWeight * directionalEnergy
        let beatTerm = config.beatStrengthWeight * beat
        let preferenceTerm = config.preferenceWeight * preference
        var s = closenessTerm + energyTerm + beatTerm + preferenceTerm

        // Prefer confident readings; low-confidence is a last resort.
        if f.bpmConfidence < config.confidenceThreshold { s *= config.lowConfidencePenalty }
        return s
    }

    /// Schmitt trigger on the cadence gap → nudge, so small wobble near a threshold
    /// doesn't thrash between SPEED_UP and SLOW_DOWN.
    @discardableResult
    private mutating func applyHysteresis(gap: Double) -> Nudge {
        let enter = config.nudgeEnterThreshold
        let exit = config.nudgeExitThreshold
        switch currentNudge {
        case .hold:
            if gap >= enter { currentNudge = .speedUp }
            else if gap <= -enter { currentNudge = .slowDown }
        case .speedUp:
            if gap <= exit { currentNudge = gap <= -enter ? .slowDown : .hold }
        case .slowDown:
            if gap >= -exit { currentNudge = gap >= enter ? .speedUp : .hold }
        }
        return currentNudge
    }
}
