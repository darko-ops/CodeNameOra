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
    ///
    /// `origins` marks which candidates came from Dromo's fallback catalog; unlisted
    /// ids count as the runner's own. It applies only as an equal-fit tiebreak.
    public mutating func selectNext(
        targetCadence: Double,
        currentCadence: Double,
        candidates: [TrackFacts],
        preferences: [String: Double] = [:],
        effectiveness: [String: LearnedEffectiveness] = [:],
        fatigue: Double = 1.0,
        origins: [String: TrackOrigin] = [:]
    ) -> Decision? {
        guard !candidates.isEmpty else { return nil }

        let gap = targetCadence - currentCadence
        let nudge = applyHysteresis(gap: gap)
        let desired = desiredBPM(targetCadence: targetCadence, gap: gap, fatigue: fatigue)

        // Rank ALL candidates on the blend — BPM shapes the score, it never gates a
        // track out (repeats are a soft penalty inside `score`, not an exclusion).
        // Deterministic: score desc, then id asc to break ties.
        var scored: [Scored] = []
        for f in candidates {
            let s = score(f, desired: desired, target: targetCadence, gap: gap,
                          preference: preferences[f.id] ?? 0,
                          learned: effectiveness[f.id] ?? .unknown,
                          fatigue: fatigue,
                          origin: origins[f.id] ?? .library)
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

    /// Convenience for callers holding bare 0…1 values with no history to model —
    /// treats each as fully earned. Live code should pass `LearnedEffectiveness` so the
    /// cold-start ramp applies.
    public mutating func selectNext(
        targetCadence: Double,
        currentCadence: Double,
        candidates: [TrackFacts],
        preferences: [String: Double] = [:],
        effectiveness: [String: Double],
        fatigue: Double = 1.0,
        origins: [String: TrackOrigin] = [:]
    ) -> Decision? {
        selectNext(targetCadence: targetCadence, currentCadence: currentCadence,
                   candidates: candidates, preferences: preferences,
                   effectiveness: effectiveness.mapValues { LearnedEffectiveness.trusted($0) },
                   fatigue: fatigue, origins: origins)
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

    /// `fatigue` (1.0 fresh → ~0.2 fatigued) softens the push: a tiring runner gets a
    /// gentler tempo target, not a harder one.
    private func desiredBPM(targetCadence: Double, gap: Double, fatigue: Double) -> Double {
        let offset = max(-config.maxBPMOffset, min(config.maxBPMOffset, gap * config.bpmPushGain))
        return targetCadence + offset * fatigue   // behind (gap>0) ⇒ push up, scaled by freshness
    }

    private func weights(_ mode: PaceMode) -> SelectionConfig.Weights {
        switch mode {
        case .push:   return config.pushWeights
        case .hold:   return config.holdWeights
        case .settle: return config.settleWeights
        }
    }

    /// "Good energy" depends on the moment: drive when pushing, calm when settling,
    /// steady-moderate when holding. When pushing, `fatigue` bends the reward from
    /// driving (spiky) energy toward sustained (moderate) energy as the runner tires —
    /// so we don't throw aggressive tracks at someone fading.
    private func energySubscore(_ energy: Double, _ mode: PaceMode, fatigue: Double) -> Double {
        switch mode {
        case .settle: return 1 - energy                   // reward calm
        case .hold:   return 1 - abs(energy - 0.5) * 2    // reward moderate
        case .push:
            let driving = energy                          // fresh: reward high energy
            let sustained = 1 - abs(energy - 0.5) * 2     // fatigued: reward steady/moderate
            return sustained + (driving - sustained) * fatigue
        }
    }

    /// Soft repeat penalty: full hit for the most-recent pick, decaying to ~0 across
    /// the window. Variety by default, but a clearly-better track can still repeat.
    private func repeatPenalty(_ id: String) -> Double {
        guard let idx = recent.lastIndex(of: id) else { return 0 }
        let fromEnd = recent.count - 1 - idx                       // 0 = most recent
        let decay = max(0, 1 - Double(fromEnd) / Double(max(1, config.recentWindow)))
        return config.repeatPenalty * decay
    }

    /// A single "how good is this track right now" score: a mode-weighted blend of
    /// tempo fit + (mode-appropriate) energy + beat strength, plus learned taste, with
    /// confidence as a multiplier and recency as a soft deduction. BPM is one input —
    /// never a gate — so a high-energy off-tempo track can win when the moment needs a push.
    ///
    /// `effectiveness` (0…1, 0.5 = neutral) is the LEARNED behavioral signal — how well
    /// this track has moved *this* runner in this mode before. It's added outside the
    /// confidence multiplier (it's ground truth, not a metadata guess) and can flip the
    /// ranking once earned, which is the point: behavior teaches the engine.
    private func score(_ f: TrackFacts, desired: Double, target: Double, gap: Double,
                       preference: Double, learned: LearnedEffectiveness, fatigue: Double,
                       origin: TrackOrigin) -> Double {
        let mode = PaceMode(gap: gap, onPaceTolerance: config.onPaceTolerance)
        let w = weights(mode)

        let eff = effectiveBPM(f, targetCadence: target)
        let tempoFit = max(0, 1 - abs(eff - desired) / config.bpmTolerance)
        let energy = energySubscore(f.energy ?? 0.5, mode, fatigue: fatigue)
        let beat = f.beatStrength ?? 0.5

        // THE GUARDRAIL: learned signals only apply inside the tempo-suitable band, so
        // learning re-ranks what fits and can never promote what doesn't. Outside it,
        // a track is judged on the objective blend alone.
        let suitable = abs(eff - desired) <= config.learningBandBPM

        // Merit: the mode-weighted blend + stated taste, discounted if low-confidence.
        var merit = w.tempo * tempoFit + w.energy * energy + w.beat * beat
        if suitable { merit += config.preferenceWeight * preference }
        if f.bpmConfidence < config.confidenceThreshold { merit *= config.lowConfidencePenalty }

        // Behavioral effectiveness sits OUTSIDE that discount (it's ground truth, not a
        // metadata guess), scaled by how much evidence stands behind it: one play barely
        // moves the ranking, several plays can flip it.
        var behavior = 0.0
        var exploration = 0.0
        if suitable {
            let trust = learned.trust(minObservations: config.minObservationsToTrust)
            behavior = config.effectivenessWeight * (learned.value - 0.5) * 2 * trust
            // Nothing measured yet ⇒ a nudge to go find out, so the learner keeps
            // getting data instead of re-playing what it already knows.
            if learned.isUnplayed { exploration = config.explorationBonus }
        }
        // Equal fit ⇒ the runner's own music wins; merit still beats provenance.
        let ownership = origin == .catalog ? config.catalogPenalty : 0
        return merit + behavior + exploration - repeatPenalty(f.id) - ownership
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
