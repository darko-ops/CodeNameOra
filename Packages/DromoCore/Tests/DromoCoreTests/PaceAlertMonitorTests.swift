import XCTest
@testable import DromoCore

final class PaceAlertMonitorTests: XCTestCase {

    private let target = 300.0   // 5:00 / km

    /// Most cases start from a runner who has already settled onto pace, since that is
    /// what arms the alarm. Arming itself is covered separately below.
    private func armed(config: PaceAlertMonitor.Config = .init()) -> PaceAlertMonitor {
        var m = PaceAlertMonitor(config: config)
        _ = m.evaluate(currentPaceSecPerKm: target, targetPaceSecPerKm: target, now: 0)
        return m
    }

    func testInRangeNeverFires() {
        var m = armed()
        // Within ±15 s of target.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 300, targetPaceSecPerKm: target, now: 0))
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 314, targetPaceSecPerKm: target, now: 1))
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 286, targetPaceSecPerKm: target, now: 2))
    }

    func testTooSlowFiresOnCrossing() {
        var m = armed()
        // 20 s/km slower than target → past the +15 threshold.
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 320, targetPaceSecPerKm: target, now: 0), .tooSlow)
    }

    func testTooFastFiresOnCrossing() {
        var m = armed()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 280, targetPaceSecPerKm: target, now: 0), .tooFast)
    }

    func testThresholdIsExclusiveAtExactly15() {
        var m = armed()
        // Exactly +15 is still in range (must exceed the threshold).
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 315, targetPaceSecPerKm: target, now: 0))
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 315.1, targetPaceSecPerKm: target, now: 1), .tooSlow)
    }

    func testDoesNotRepeatBeforeInterval() {
        var m = armed()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        // Still slow but only 14 s later → no repeat yet.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 14))
    }

    func testRepeatsEvery15Seconds() {
        var m = armed()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 10))
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 15), .tooSlow)
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 30), .tooSlow)
    }

    func testReturningToRangeResetsAndRefiresOnNextExit() {
        var m = armed()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        // Back in range — clears the clock.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 300, targetPaceSecPerKm: target, now: 5))
        // Exits again shortly after → fires immediately (not gated by the 15 s window).
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 6), .tooSlow)
    }

    func testSwitchingSidesFiresImmediately() {
        var m = armed()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        // Jumps straight to too-fast 2 s later → fires the other cue at once.
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 270, targetPaceSecPerKm: target, now: 2), .tooFast)
    }

    func testUnknownPaceIsSilentAndResets() {
        var m = armed()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        // GPS drops out (pace 0) → silent and resets.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 0, targetPaceSecPerKm: target, now: 1))
        // When a valid out-of-range pace returns, it fires fresh.
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 2), .tooSlow)
    }

    func testCustomThreshold() {
        var m = armed(config: .init(thresholdSeconds: 10, repeatInterval: 30))
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 312, targetPaceSecPerKm: target, now: 0), .tooSlow)
    }

    // MARK: - Arming

    /// The first minute of a run is spent getting up to pace. Alarming through it is
    /// noise, not coaching, so nothing sounds until the runner has actually been on pace.
    func testStaysSilentUntilTheRunnerReachesTheBand() {
        var m = PaceAlertMonitor()
        XCTAssertFalse(m.isActive)
        // Starting from a standstill: far too slow for a while, and silent throughout.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 600, targetPaceSecPerKm: target, now: 0))
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 480, targetPaceSecPerKm: target, now: 10))
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 360, targetPaceSecPerKm: target, now: 20))
        XCTAssertNil(m.activeAlert, "The HUD must not shout while the sound is holding off")
    }

    func testArmsOnReachingTheBandThenFiresOnLeavingIt() {
        var m = PaceAlertMonitor()
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 600, targetPaceSecPerKm: target, now: 0))
        // Reaches target pace — the band is now live, and reaching it is itself silent.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 302, targetPaceSecPerKm: target, now: 30))
        XCTAssertTrue(m.isActive)
        // Drifts back out → this one sounds.
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 40), .tooSlow)
        XCTAssertEqual(m.activeAlert, .tooSlow)
    }

    /// Arming is once per run. A runner who settles, drifts off and stays off is still
    /// owed the repeat — they don't have to re-qualify by getting back on pace first.
    func testArmingSurvivesGoingOutOfRange() {
        var m = PaceAlertMonitor()
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 300, targetPaceSecPerKm: target, now: 0))
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 340, targetPaceSecPerKm: target, now: 5), .tooSlow)
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 340, targetPaceSecPerKm: target, now: 20), .tooSlow)
        XCTAssertTrue(m.isActive)
    }

    /// A dropout reports pace 0, which the monitor treats as in-range so the band resets
    /// cleanly. That must not count as having reached the band: "no reading" is not
    /// "on pace", and taking it as one would arm the alarm on a runner who never was.
    func testAGPSDropoutDoesNotArmTheAlarm() {
        var m = PaceAlertMonitor()
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 0, targetPaceSecPerKm: target, now: 0))
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 0, targetPaceSecPerKm: target, now: 5))
        XCTAssertFalse(m.isActive)
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 400, targetPaceSecPerKm: target, now: 10))
    }
}
