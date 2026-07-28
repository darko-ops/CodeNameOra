import XCTest
@testable import DromoCore

/// Phase 7 exit gate: cues fire correctly from simulated pace data, and never during a
/// track transition — the coach sits ON the music, never in place of it.
final class CoachCueEngineTests: XCTestCase {

    private func engine(_ configure: (inout CoachCueEngine.Config) -> Void = { _ in })
        -> CoachCueEngine {
        var config = CoachCueEngine.Config()
        configure(&config)
        return CoachCueEngine(config: config, isEnabled: true)
    }

    private func sample(distance: Double, elapsed: Double, pace: Double = 300,
                        target: Double = 300, goal: Double? = nil,
                        transitioning: Bool = false) -> CoachCueEngine.Sample {
        CoachCueEngine.Sample(distanceMeters: distance, elapsedSeconds: elapsed,
                             paceSecPerKm: pace, targetPaceSecPerKm: target,
                             goalMeters: goal, isTransitioning: transitioning)
    }

    /// Runs a simulated run at a steady pace, collecting whatever the coach says.
    private func simulate(_ coach: inout CoachCueEngine, seconds: Int, paceSecPerKm: Double,
                          target: Double = 300, goal: Double? = nil,
                          transitionAt: Set<Int> = []) -> [CoachCue] {
        var cues: [CoachCue] = []
        for second in 1...seconds {
            let distance = (1_000.0 / paceSecPerKm) * Double(second)
            if let cue = coach.update(sample(distance: distance, elapsed: Double(second),
                                             pace: paceSecPerKm, target: target, goal: goal,
                                             transitioning: transitionAt.contains(second))) {
                cues.append(cue)
            }
        }
        return cues
    }

    // MARK: - Off by default

    func testSaysNothingUnlessTurnedOn() {
        var coach = CoachCueEngine()           // isEnabled defaults to false
        let cues = simulate(&coach, seconds: 1_800, paceSecPerKm: 330)
        XCTAssertTrue(cues.isEmpty, "the DJ works with no coach at all")
    }

    // MARK: - Splits

    func testAnnouncesEachKilometreOnce() {
        var coach = engine()
        // 5:00/km for 20 minutes ⇒ 4 km.
        let cues = simulate(&coach, seconds: 1_200, paceSecPerKm: 300)
        let splits = cues.compactMap { cue -> Int? in
            if case let .split(index, _, _) = cue { return index }
            return nil
        }
        XCTAssertEqual(splits, [1, 2, 3, 4], "one cue per km, in order, no repeats")
    }

    func testSplitReportsThatSplitsPaceNotTheWholeRun() {
        var coach = engine { $0.minGapSeconds = 0 }
        // First km slow (6:00), second km fast (4:00).
        _ = coach.update(sample(distance: 1_000, elapsed: 360, pace: 360))
        let cue = coach.update(sample(distance: 2_000, elapsed: 600, pace: 240))

        guard case let .split(index, pace, delta) = cue else { return XCTFail("expected a split") }
        XCTAssertEqual(index, 2)
        XCTAssertEqual(pace, 240, accuracy: 1, "second km took 240 s, not the run average")
        XCTAssertEqual(delta, -60, accuracy: 1, "60 s/km faster than the 5:00 target")
    }

    func testSplitSpeechIsShortAndSaysTheComparison() {
        let fast = CoachCue.split(index: 2, paceSecPerKm: 270, deltaVsTargetSec: -30)
        XCTAssertEqual(fast.spoken, "Kilometre 2. 4 30 per kilometre. 30 seconds fast.")

        let onTarget = CoachCue.split(index: 3, paceSecPerKm: 301, deltaVsTargetSec: 1)
        XCTAssertTrue(onTarget.spoken.hasSuffix("on target."),
                      "a 1-second difference is not worth a correction")
    }

    // MARK: - Goal pace

    func testGoalPaceCueRespectsItsIntervalAndDeadband() {
        var coach = engine { $0.goalPaceIntervalSeconds = 120 }
        // Running 20 s/km slow for 10 minutes: cues, but not a stream of them.
        let cues = simulate(&coach, seconds: 600, paceSecPerKm: 320)
        let checks = cues.filter { if case .goalPace = $0 { return true } else { return false } }
        XCTAssertGreaterThan(checks.count, 0)
        XCTAssertLessThanOrEqual(checks.count, 5, "a coach that chatters is worse than none")
    }

    func testNoGoalPaceCueWhenEssentiallyOnPace() {
        var coach = engine { $0.goalPaceIntervalSeconds = 60 }
        let cues = simulate(&coach, seconds: 900, paceSecPerKm: 302)   // 2 s/km off
        XCTAssertFalse(cues.contains { if case .goalPace = $0 { return true } else { return false } },
                       "2 s/km is inside the deadband — nothing to say")
    }

    func testGoalPaceSpeechNamesTheDirection() {
        XCTAssertTrue(CoachCue.goalPace(deltaSecPerKm: 12).spoken.contains("behind"))
        XCTAssertTrue(CoachCue.goalPace(deltaSecPerKm: -12).spoken.contains("ahead"))
        XCTAssertEqual(CoachCue.goalPace(deltaSecPerKm: 1).spoken, "Right on pace.")
    }

    // MARK: - Negative split + finish

    func testHalfwayCueAsksForAFasterSecondHalf() {
        var coach = engine { $0.minGapSeconds = 0 }
        // 5 km goal, first half run 20 s/km slow. Splits are owed first (they're due
        // every km), so halfway guidance lands on a following sample — one second
        // later in a real run at 1 Hz.
        var cue: CoachCue?
        for second in stride(from: 320, through: 810, by: 10) {
            let distance = (1_000.0 / 320.0) * Double(second)
            if let emitted = coach.update(sample(distance: distance, elapsed: Double(second),
                                                 pace: 320, goal: 5_000)),
               case .negativeSplit = emitted {
                cue = emitted
                break
            }
        }
        guard case let .negativeSplit(first, second) = cue else {
            return XCTFail("expected halfway guidance")
        }
        XCTAssertEqual(first, 320, accuracy: 2)
        XCTAssertLessThan(second, first, "a negative split means the rest is faster")
        XCTAssertTrue(cue?.spoken.contains("Halfway") == true)
    }

    func testHalfwayGuidanceNeverDemandsTheImpossible() {
        var coach = engine { $0.minGapSeconds = 0 }
        // Wildly off target (target 4:00, running 7:00): the honest ask is "faster",
        // not a pace no runner could produce after fading that badly.
        var cue: CoachCue?
        for second in stride(from: 420, through: 1_100, by: 10) {
            let distance = (1_000.0 / 420.0) * Double(second)
            if let emitted = coach.update(sample(distance: distance, elapsed: Double(second),
                                                 pace: 420, target: 240, goal: 5_000)),
               case .negativeSplit = emitted {
                cue = emitted
                break
            }
        }
        guard case let .negativeSplit(first, second) = cue else { return XCTFail("expected cue") }
        XCTAssertGreaterThanOrEqual(second, first * 0.85, "capped at a 15% lift")
    }

    func testHalfwayAndFinishAreAnnouncedOnce() {
        var coach = engine { $0.minGapSeconds = 0 }
        let cues = simulate(&coach, seconds: 1_500, paceSecPerKm: 300, goal: 3_000)
        let halfway = cues.filter { if case .negativeSplit = $0 { return true } else { return false } }
        let finish = cues.filter { if case .finish = $0 { return true } else { return false } }
        XCTAssertEqual(halfway.count, 1)
        XCTAssertEqual(finish.count, 1)
    }

    func testFlushClosesOutARunWithoutAGoal() {
        var coach = engine()
        _ = simulate(&coach, seconds: 600, paceSecPerKm: 300)
        let cue = coach.flush(sample(distance: 2_000, elapsed: 600, pace: 300))
        guard case let .finish(elapsed, pace) = cue else { return XCTFail("expected a finish cue") }
        XCTAssertEqual(elapsed, 600)
        XCTAssertEqual(pace, 300, accuracy: 1)
        XCTAssertNil(coach.flush(sample(distance: 2_000, elapsed: 600)), "said once, not twice")
    }

    // MARK: - The guarantee: never over a crossfade

    func testNoCueFiresWhileATrackIsChanging() {
        var coach = engine { $0.minGapSeconds = 0 }
        // A split falls due exactly while a crossfade is running.
        let held = coach.update(sample(distance: 1_000, elapsed: 300, transitioning: true))
        XCTAssertNil(held, "a cue here would talk over the crossfade")

        // …and it isn't lost: it fires as soon as the transition ends.
        let released = coach.update(sample(distance: 1_010, elapsed: 301))
        guard case let .split(index, _, _) = released else {
            return XCTFail("the owed split must still arrive")
        }
        XCTAssertEqual(index, 1)
    }

    func testTransitionsThroughoutARunNeverProduceACueMidChange() {
        // Simulate a run where every 30th second is a transition; assert the coach
        // never speaks on one of those seconds.
        var coach = engine { $0.minGapSeconds = 10 }
        let transitions = Set(stride(from: 30, through: 1_200, by: 30))
        var spokeDuringTransition = false
        for second in 1...1_200 {
            let isTransition = transitions.contains(second)
            let distance = (1_000.0 / 300.0) * Double(second)
            if coach.update(sample(distance: distance, elapsed: Double(second),
                                   transitioning: isTransition)) != nil, isTransition {
                spokeDuringTransition = true
            }
        }
        XCTAssertFalse(spokeDuringTransition)
    }

    // MARK: - Restraint

    func testCuesAreSpacedByTheMinimumGap() {
        var coach = engine { $0.minGapSeconds = 60; $0.goalPaceIntervalSeconds = 30 }
        var lastAt: Double = -.infinity
        var violations = 0
        for second in 1...1_800 {
            let distance = (1_000.0 / 330.0) * Double(second)
            if coach.update(sample(distance: distance, elapsed: Double(second),
                                   pace: 330)) != nil {
                if Double(second) - lastAt < 60 { violations += 1 }
                lastAt = Double(second)
            }
        }
        XCTAssertEqual(violations, 0)
    }

    func testNothingIsSaidDuringTheWarmup() {
        var coach = engine { $0.warmupSeconds = 120; $0.goalPaceIntervalSeconds = 10 }
        var cues: [CoachCue] = []
        for second in 1...119 {
            if let cue = coach.update(sample(distance: Double(second) * 3, elapsed: Double(second),
                                             pace: 400)) {
                cues.append(cue)
            }
        }
        XCTAssertTrue(cues.isEmpty, "early pace is noise; correcting it would be wrong")
    }
}
