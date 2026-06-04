import XCTest
@testable import DromoCore

final class SelectionEngineTests: XCTestCase {

    private func facts(_ id: String, bpm: Double, energy: Double = 0.5,
                       beat: Double = 0.6, confidence: Double = 0.9,
                       octave: AnalysisResult.OctaveFlag = .none) -> TrackFacts {
        TrackFacts(id: id, bpm: bpm, bpmConfidence: confidence, tempoOctaveFlag: octave,
                   energy: energy, beatStrength: beat, analysisVersion: "vdsp-1")
    }

    // MARK: Behind / ahead / on-pace bias

    func testBehindPaceSelectsHigherBPMAndEnergy() {
        var engine = SelectionEngine()
        let pool = [facts("slow", bpm: 150, energy: 0.4), facts("fast", bpm: 180, energy: 0.8)]
        let d = engine.selectNext(targetCadence: 170, currentCadence: 150, candidates: pool)
        XCTAssertEqual(d?.trackID, "fast")
        XCTAssertEqual(d?.nudge, .speedUp)
    }

    func testAheadOfPaceSelectsLowerBPMAndCalmer() {
        var engine = SelectionEngine()
        let pool = [facts("slow", bpm: 150, energy: 0.3), facts("fast", bpm: 180, energy: 0.8)]
        let d = engine.selectNext(targetCadence: 170, currentCadence: 190, candidates: pool)
        XCTAssertEqual(d?.trackID, "slow")
        XCTAssertEqual(d?.nudge, .slowDown)
    }

    func testOnPaceSelectsNearTargetAndHolds() {
        var engine = SelectionEngine()
        let pool = [facts("near", bpm: 168, energy: 0.5), facts("far", bpm: 185, energy: 0.5)]
        let d = engine.selectNext(targetCadence: 170, currentCadence: 170, candidates: pool)
        XCTAssertEqual(d?.trackID, "near")
        XCTAssertEqual(d?.nudge, .hold)
    }

    // MARK: Octave resolution (85-vs-170)

    func testOctaveResolvesToCadence_doubleFlag() {
        let engine = SelectionEngine()
        let track = facts("x", bpm: 85, octave: .double)   // true tempo may be 170
        XCTAssertEqual(engine.effectiveBPM(track, targetCadence: 170), 170)
        XCTAssertEqual(engine.effectiveBPM(track, targetCadence: 90), 85)
    }

    func testOctaveResolvesToCadence_halfFlag() {
        let engine = SelectionEngine()
        let track = facts("x", bpm: 170, octave: .half)    // true tempo may be 85
        XCTAssertEqual(engine.effectiveBPM(track, targetCadence: 85), 85)
        XCTAssertEqual(engine.effectiveBPM(track, targetCadence: 170), 170)
    }

    func testHalfTimeTrackChosenForFastRunner() {
        var engine = SelectionEngine()
        // An 85-BPM-stored, double-flagged track should win for a 170 runner because
        // its effective tempo resolves to 170.
        let pool = [facts("real85", bpm: 85, octave: .none),
                    facts("half", bpm: 85, energy: 0.7, octave: .double)]
        let d = engine.selectNext(targetCadence: 170, currentCadence: 170, candidates: pool)
        XCTAssertEqual(d?.trackID, "half")
        XCTAssertEqual(d?.effectiveBPM, 170)
    }

    // MARK: Hysteresis (no thrash)

    func testHysteresisPreventsThrash() {
        var engine = SelectionEngine()   // enter 8, exit 4
        XCTAssertEqual(engine.updateNudge(targetCadence: 170, currentCadence: 168), .hold)   // gap 2
        XCTAssertEqual(engine.updateNudge(targetCadence: 170, currentCadence: 161), .speedUp) // gap 9
        XCTAssertEqual(engine.updateNudge(targetCadence: 170, currentCadence: 165), .speedUp) // gap 5 (>exit)
        XCTAssertEqual(engine.updateNudge(targetCadence: 170, currentCadence: 164), .speedUp) // gap 6
        XCTAssertEqual(engine.updateNudge(targetCadence: 170, currentCadence: 167), .hold)    // gap 3 (<exit)
    }

    func testHysteresisFlipsAcrossZeroOnlyWhenStrong() {
        var engine = SelectionEngine()
        _ = engine.updateNudge(targetCadence: 170, currentCadence: 160)                       // gap 10 → speedUp
        XCTAssertEqual(engine.updateNudge(targetCadence: 170, currentCadence: 180), .slowDown) // gap -10 → flip
    }

    // MARK: Confidence, repeats, determinism, config

    func testLowConfidenceIsLastResort() {
        var engine = SelectionEngine()
        let pool = [facts("sure", bpm: 170, confidence: 0.9),
                    facts("guess", bpm: 170, confidence: 0.2)]
        let d = engine.selectNext(targetCadence: 170, currentCadence: 170, candidates: pool)
        XCTAssertEqual(d?.trackID, "sure")
    }

    func testRepeatAvoidance() {
        var engine = SelectionEngine()
        let pool = [facts("a", bpm: 168), facts("b", bpm: 170), facts("c", bpm: 172)]
        var picks: [String] = []
        for _ in 0..<3 {
            if let d = engine.selectNext(targetCadence: 170, currentCadence: 170, candidates: pool) {
                picks.append(d.trackID)
            }
        }
        XCTAssertEqual(Set(picks).count, 3, "should not repeat within the window")
    }

    func testDeterministic() {
        var a = SelectionEngine(), b = SelectionEngine()
        let pool = [facts("x", bpm: 165), facts("y", bpm: 175), facts("z", bpm: 185)]
        let d1 = a.selectNext(targetCadence: 172, currentCadence: 160, candidates: pool)
        let d2 = b.selectNext(targetCadence: 172, currentCadence: 160, candidates: pool)
        XCTAssertEqual(d1, d2)
    }

    func testThresholdsAreConfigurable() {
        // With a tiny enter threshold, a small gap should now trigger speed-up.
        var config = SelectionConfig()
        config.nudgeEnterThreshold = 2
        config.nudgeExitThreshold = 1
        var engine = SelectionEngine(config: config)
        XCTAssertEqual(engine.updateNudge(targetCadence: 170, currentCadence: 167), .speedUp) // gap 3
    }

    func testEmptyPoolReturnsNil() {
        var engine = SelectionEngine()
        XCTAssertNil(engine.selectNext(targetCadence: 170, currentCadence: 170, candidates: []))
    }

    func testPreferenceBreaksOtherwiseEqualCandidates() {
        var engine = SelectionEngine()
        let pool = [facts("plain", bpm: 170), facts("loved", bpm: 170)]
        let d = engine.selectNext(targetCadence: 170, currentCadence: 170,
                                  candidates: pool, preferences: ["loved": 1.0])
        XCTAssertEqual(d?.trackID, "loved")
    }
}
