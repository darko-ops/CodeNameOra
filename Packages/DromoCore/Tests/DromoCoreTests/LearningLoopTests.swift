import XCTest
@testable import DromoCore

/// Phase 5 exit gate: the learning loop as a whole — signal derivation, EMA updates,
/// how evidence enters the blend, cold-start exploration, and the guardrail that keeps
/// learning from ever picking a tempo-inappropriate track.
final class LearningLoopTests: XCTestCase {

    private func facts(_ id: String, bpm: Double, energy: Double = 0.5) -> TrackFacts {
        TrackFacts(id: id, bpm: bpm, bpmConfidence: 0.9, tempoOctaveFlag: .none,
                   energy: energy, beatStrength: 0.7, durationMs: 200_000,
                   analysisVersion: "test")
    }

    // MARK: - Signal derivation

    func testRewardIsGapClosedWhileTheTrackPlayed() {
        var attributor = PaceResponseAttributor()
        // Behind by 10 spm when the track starts, behind by 2 when it ends: it helped.
        _ = attributor.observe(trackID: "a", targetCadence: 170, currentCadence: 160)
        _ = attributor.observe(trackID: "a", targetCadence: 170, currentCadence: 165)
        _ = attributor.observe(trackID: "a", targetCadence: 170, currentCadence: 168)
        let response = attributor.flush()

        XCTAssertEqual(response?.trackID, "a")
        XCTAssertEqual(response?.mode, .push, "it started behind pace")
        XCTAssertEqual(response?.reward ?? 0, 8, accuracy: 0.001, "|gap| 10 → 2")
    }

    func testTrackThatLostGroundEarnsNegativeReward() {
        var attributor = PaceResponseAttributor()
        for cadence in [168.0, 164, 158] {
            _ = attributor.observe(trackID: "a", targetCadence: 170, currentCadence: cadence)
        }
        let response = attributor.flush()
        XCTAssertLessThan(response?.reward ?? 0, 0, "drifting further behind is a negative signal")
    }

    func testResponseIsEmittedOnTrackChangeAndKeyedToTheModeActedOn() {
        var attributor = PaceResponseAttributor()
        for _ in 0..<4 {
            _ = attributor.observe(trackID: "a", targetCadence: 170, currentCadence: 150)
        }
        // Switching tracks closes out "a" — mode from ITS opening gap, not the new one.
        let emitted = attributor.observe(trackID: "b", targetCadence: 170, currentCadence: 172)
        XCTAssertEqual(emitted?.trackID, "a")
        XCTAssertEqual(emitted?.mode, .push)
    }

    func testUltraShortPlaysAreNotAttributed() {
        var attributor = PaceResponseAttributor()
        _ = attributor.observe(trackID: "a", targetCadence: 170, currentCadence: 160)
        XCTAssertNil(attributor.flush(), "an instant skip carries no usable signal")
    }

    // MARK: - EMA updates

    func testEMAMovesTowardTheObservationWithoutJumpingToIt() {
        let learner = EffectivenessLearner()
        let first = learner.updated(previous: nil, reward: 8)      // strong positive
        XCTAssertGreaterThan(first, 0.5)
        XCTAssertLessThan(first, 1.0, "one play must not saturate the estimate")

        let second = learner.updated(previous: first, reward: 8)
        XCTAssertGreaterThan(second, first, "repeated evidence keeps moving it")
    }

    func testRewardScoreIsCenteredAndClamped() {
        let learner = EffectivenessLearner()
        XCTAssertEqual(learner.rewardScore(0), 0.5, accuracy: 0.001, "no change ⇒ neutral")
        XCTAssertEqual(learner.rewardScore(999), 1.0, accuracy: 0.001)
        XCTAssertEqual(learner.rewardScore(-999), 0.0, accuracy: 0.001)
    }

    func testStoreCountsObservationsPerMode() async {
        let store = InMemoryEffectivenessStore()
        await store.record(TrackResponse(trackID: "a", mode: .push, reward: 6, samples: 20))
        await store.record(TrackResponse(trackID: "a", mode: .push, reward: 6, samples: 20))
        await store.record(TrackResponse(trackID: "a", mode: .hold, reward: -4, samples: 20))

        let push = await store.learned(for: .push)["a"]
        let hold = await store.learned(for: .hold)["a"]
        XCTAssertEqual(push?.observations, 2)
        XCTAssertEqual(hold?.observations, 1, "learning is per-mode, not global")
        XCTAssertGreaterThan(push?.value ?? 0, 0.5)
        XCTAssertLessThan(hold?.value ?? 1, 0.5)
    }

    // MARK: - Blend: evidence earns influence

    /// The property the prompt asks for: until a track has `minObservationsToTrust`
    /// plays, tempo fit decides. Swept across the whole ramp rather than spot-checked.
    func testTempoFitDominatesUntilEffectivenessIsEarned() {
        let config = SelectionConfig()
        let onTempo = facts("onTempo", bpm: 170)
        let proven = facts("proven", bpm: 162)          // 8 BPM worse fit

        for observations in 0..<config.minObservationsToTrust {
            var engine = SelectionEngine()
            let decision = engine.selectNext(
                targetCadence: 170, currentCadence: 170,
                candidates: [onTempo, proven],
                effectiveness: ["proven": LearnedEffectiveness(value: 1.0,
                                                              observations: observations)])
            XCTAssertEqual(decision?.trackID, "onTempo",
                           "with \(observations) observation(s), tempo fit must still decide")
        }

        // At the threshold the earned signal is allowed to flip it.
        var engine = SelectionEngine()
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170,
            candidates: [onTempo, proven],
            effectiveness: ["proven": LearnedEffectiveness(
                value: 1.0, observations: config.minObservationsToTrust)])
        XCTAssertEqual(decision?.trackID, "proven", "evidence, once earned, can win")
    }

    func testTrustRampIsMonotonic() {
        // More evidence must never mean less influence.
        var previous = -1.0
        for n in 0...10 {
            let trust = LearnedEffectiveness(value: 0.9, observations: n).trust(minObservations: 4)
            XCTAssertGreaterThanOrEqual(trust, previous)
            XCTAssertLessThanOrEqual(trust, 1.0)
            previous = trust
        }
    }

    func testProvenBadTrackIsDemotedOnceEarned() {
        var engine = SelectionEngine()
        let neutral = facts("neutral", bpm: 168)
        let dud = facts("dud", bpm: 170)                // better tempo, but it drags
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170,
            candidates: [neutral, dud],
            effectiveness: ["dud": .trusted(0.0)])
        XCTAssertEqual(decision?.trackID, "neutral", "demonstrated failure outranks a tidy BPM")
    }

    // MARK: - Cold start

    func testUnplayedTrackIsExploredOverAnEquallyFittingKnownOne() {
        var engine = SelectionEngine()
        let known = facts("known", bpm: 170)
        let fresh = facts("fresh", bpm: 170)            // identical facts, never played
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170,
            candidates: [known, fresh],
            effectiveness: ["known": LearnedEffectiveness(value: 0.5, observations: 5)])
        XCTAssertEqual(decision?.trackID, "fresh",
                       "with nothing to separate them, go find out about the new one")
    }

    func testExplorationDoesNotOutweighDemonstratedSuccess() {
        var engine = SelectionEngine()
        let proven = facts("proven", bpm: 170)
        let fresh = facts("fresh", bpm: 170)
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170,
            candidates: [proven, fresh],
            effectiveness: ["proven": .trusted(1.0)])
        XCTAssertEqual(decision?.trackID, "proven", "curiosity is a nudge, not a coin flip")
    }

    func testExplorationNeverReachesOutsideTheSuitableBand() {
        var engine = SelectionEngine()
        let suitable = facts("suitable", bpm: 170)
        let wrongTempo = facts("wrongTempo", bpm: 120)   // unplayed, but far off-tempo
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170,
            candidates: [suitable, wrongTempo],
            effectiveness: ["suitable": LearnedEffectiveness(value: 0.5, observations: 9)])
        XCTAssertEqual(decision?.trackID, "suitable")
    }

    // MARK: - The guardrail

    func testLearningCannotPromoteATempoInappropriateTrack() {
        var engine = SelectionEngine()
        let suitable = facts("suitable", bpm: 170)
        // The runner's demonstrated favourite — at half the required tempo.
        let beloved = facts("beloved", bpm: 90)
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170,
            candidates: [suitable, beloved],
            preferences: ["beloved": 1.0],
            effectiveness: ["beloved": .trusted(1.0)])
        XCTAssertEqual(decision?.trackID, "suitable",
                       "no amount of learning may pace a 170 spm runner to 90 BPM")
    }

    func testGuardrailHoldsAcrossTheWholeTempoRange() {
        // Sweep: for every target, a maximally-proven, maximally-liked track that sits
        // outside the band must lose to an unproven track inside it.
        for target in stride(from: 130.0, through: 190.0, by: 5) {
            let config = SelectionConfig()
            let outside = facts("outside", bpm: target - config.learningBandBPM - 20)
            let inside = facts("inside", bpm: target)
            var engine = SelectionEngine()
            let decision = engine.selectNext(
                targetCadence: target, currentCadence: target,
                candidates: [outside, inside],
                preferences: ["outside": 1.0],
                effectiveness: ["outside": .trusted(1.0)])
            XCTAssertEqual(decision?.trackID, "inside", "guardrail leaked at target \(target)")
        }
    }

    func testLearningStillReRanksWithinTheSuitableSet() {
        // The guardrail must not neuter learning: inside the band, evidence decides.
        var engine = SelectionEngine()
        let a = facts("a", bpm: 170)
        let b = facts("b", bpm: 166)
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170,
            candidates: [a, b],
            effectiveness: ["b": .trusted(1.0), "a": .trusted(0.2)])
        XCTAssertEqual(decision?.trackID, "b", "within tempo-suitable, behaviour rules")
    }

    // MARK: - The loop, end to end

    /// The exit gate's headline: run several simulated sessions and show selections
    /// shifting toward tracks that actually moved the runner.
    func testSimulatedSessionsShiftSelectionTowardHighRewardTracks() async {
        let store = InMemoryEffectivenessStore()
        let pool = [facts("mover", bpm: 168), facts("drag", bpm: 170), facts("plain", bpm: 169)]
        // Ground truth the runner's body enacts: "mover" closes the gap, "drag" loses it.
        let rewardFor = ["mover": 7.0, "drag": -7.0, "plain": 0.0]

        var picks: [String] = []
        for session in 0..<6 {
            var engine = SelectionEngine()
            let learned = await store.learned(for: .push)
            // Behind pace ⇒ push mode, the mode the rewards were recorded in.
            guard let decision = engine.selectNext(targetCadence: 170, currentCadence: 158,
                                                   candidates: pool, effectiveness: learned)
            else { return XCTFail("no selection in session \(session)") }
            picks.append(decision.trackID)
            await store.record(TrackResponse(trackID: decision.trackID, mode: .push,
                                             reward: rewardFor[decision.trackID] ?? 0,
                                             samples: 30))
        }

        // Early on it explores; by the end it has learned who actually moves this runner.
        XCTAssertEqual(Set(picks.prefix(3)).count, 3, "explores the pool before committing")
        XCTAssertEqual(picks.suffix(2), ["mover", "mover"], "settles on what works: \(picks)")

        let final = await store.learned(for: .push)
        XCTAssertGreaterThan(final["mover"]?.value ?? 0, final["drag"]?.value ?? 1)
        XCTAssertEqual(final["drag"]?.observations, 1, "one bad play was enough to stop choosing it")
    }
}
