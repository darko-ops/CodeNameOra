import XCTest
@testable import DromoCore

final class PaceResponseTests: XCTestCase {

    // MARK: PaceMode classification

    func testPaceModeFromGap() {
        XCTAssertEqual(PaceMode(gap: 10, onPaceTolerance: 4), .push)    // behind
        XCTAssertEqual(PaceMode(gap: -10, onPaceTolerance: 4), .settle) // ahead
        XCTAssertEqual(PaceMode(gap: 2, onPaceTolerance: 4), .hold)
    }

    // MARK: Attributor

    /// Behind pace, then the runner speeds up while a track plays → positive reward,
    /// attributed to that track, classified as a push.
    func testAttributorRewardsClosingTheGap() {
        var a = PaceResponseAttributor()
        // Track "drive" plays while cadence climbs 150 → 168 toward a 170 target.
        XCTAssertNil(a.observe(trackID: "drive", targetCadence: 170, currentCadence: 150))
        _ = a.observe(trackID: "drive", targetCadence: 170, currentCadence: 160)
        _ = a.observe(trackID: "drive", targetCadence: 170, currentCadence: 168)
        // Track changes → previous track's response is emitted.
        let r = a.observe(trackID: "next", targetCadence: 170, currentCadence: 168)
        XCTAssertEqual(r?.trackID, "drive")
        XCTAssertEqual(r?.mode, .push)
        XCTAssertEqual(r?.reward ?? 0, 18, accuracy: 0.001)   // |170-150| - |170-168| = 20 - 2
    }

    func testAttributorNegativeWhenGapWidens() {
        var a = PaceResponseAttributor()
        _ = a.observe(trackID: "drag", targetCadence: 170, currentCadence: 165) // gap 5
        _ = a.observe(trackID: "drag", targetCadence: 170, currentCadence: 160)
        _ = a.observe(trackID: "drag", targetCadence: 170, currentCadence: 150) // gap 20 (worse)
        let r = a.flush()
        XCTAssertEqual(r?.trackID, "drag")
        XCTAssertEqual(r?.reward ?? 0, -15, accuracy: 0.001)   // 5 - 20
    }

    func testAttributorIgnoresUltraShortPlays() {
        var a = PaceResponseAttributor()   // minSamples 3
        _ = a.observe(trackID: "blip", targetCadence: 170, currentCadence: 150)
        // Switches after only 1 sample → nothing to learn.
        let r = a.observe(trackID: "other", targetCadence: 170, currentCadence: 150)
        XCTAssertNil(r)
    }

    func testFlushEmitsCurrentTrack() {
        var a = PaceResponseAttributor()
        _ = a.observe(trackID: "t", targetCadence: 170, currentCadence: 160)
        _ = a.observe(trackID: "t", targetCadence: 170, currentCadence: 165)
        _ = a.observe(trackID: "t", targetCadence: 170, currentCadence: 169)
        XCTAssertEqual(a.flush()?.trackID, "t")
        XCTAssertNil(a.flush())   // nothing left after flushing
    }

    // MARK: Learner

    func testRewardScoreCentersAtNeutral() {
        let l = EffectivenessLearner()
        XCTAssertEqual(l.rewardScore(0), 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(l.rewardScore(8), 0.5)
        XCTAssertLessThan(l.rewardScore(-8), 0.5)
        XCTAssertEqual(l.rewardScore(100), 1, accuracy: 0.001)   // clamped
        XCTAssertEqual(l.rewardScore(-100), 0, accuracy: 0.001)  // clamped
    }

    func testLearnerEMAMovesTowardObservation() {
        let l = EffectivenessLearner()
        // From neutral, a strong positive reward should raise the estimate.
        let up = l.updated(previous: nil, reward: 16)
        XCTAssertGreaterThan(up, 0.5)
        // A strong negative reward should lower it.
        let down = l.updated(previous: 0.5, reward: -16)
        XCTAssertLessThan(down, 0.5)
    }

    // MARK: Store

    func testInMemoryStoreLearnsPerMode() async {
        let store = InMemoryEffectivenessStore()
        await store.record(TrackResponse(trackID: "x", mode: .push, reward: 16, samples: 5))
        let push = await store.effectiveness(for: .push)
        let hold = await store.effectiveness(for: .hold)
        XCTAssertGreaterThan(push["x"] ?? 0, 0.5)   // learned in push
        XCTAssertNil(hold["x"])                       // not in hold — kept separate
    }
}
