import XCTest
@testable import DromoCore

final class PaceAlertMonitorTests: XCTestCase {

    private let target = 300.0   // 5:00 / km

    func testInRangeNeverFires() {
        var m = PaceAlertMonitor()
        // Within ±20 s of target.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 300, targetPaceSecPerKm: target, now: 0))
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 319, targetPaceSecPerKm: target, now: 1))
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 281, targetPaceSecPerKm: target, now: 2))
    }

    func testTooSlowFiresOnCrossing() {
        var m = PaceAlertMonitor()
        // 25 s/km slower than target → past the +20 threshold.
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 325, targetPaceSecPerKm: target, now: 0), .tooSlow)
    }

    func testTooFastFiresOnCrossing() {
        var m = PaceAlertMonitor()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 275, targetPaceSecPerKm: target, now: 0), .tooFast)
    }

    func testThresholdIsExclusiveAtExactly20() {
        var m = PaceAlertMonitor()
        // Exactly +20 is still in range (must exceed the threshold).
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 320, targetPaceSecPerKm: target, now: 0))
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 320.1, targetPaceSecPerKm: target, now: 1), .tooSlow)
    }

    func testDoesNotRepeatBeforeInterval() {
        var m = PaceAlertMonitor()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        // Still slow but only 29 s later → no repeat yet.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 29))
    }

    func testRepeatsAfter30Seconds() {
        var m = PaceAlertMonitor()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 20))
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 30), .tooSlow)
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 60), .tooSlow)
    }

    func testReturningToRangeResetsAndRefiresOnNextExit() {
        var m = PaceAlertMonitor()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        // Back in range — clears the clock.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 300, targetPaceSecPerKm: target, now: 5))
        // Exits again shortly after → fires immediately (not gated by the 30 s window).
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 6), .tooSlow)
    }

    func testSwitchingSidesFiresImmediately() {
        var m = PaceAlertMonitor()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        // Jumps straight to too-fast 2 s later → fires the other cue at once.
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 270, targetPaceSecPerKm: target, now: 2), .tooFast)
    }

    func testUnknownPaceIsSilentAndResets() {
        var m = PaceAlertMonitor()
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 0), .tooSlow)
        // GPS drops out (pace 0) → silent and resets.
        XCTAssertNil(m.evaluate(currentPaceSecPerKm: 0, targetPaceSecPerKm: target, now: 1))
        // When a valid out-of-range pace returns, it fires fresh.
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 330, targetPaceSecPerKm: target, now: 2), .tooSlow)
    }

    func testCustomThreshold() {
        var m = PaceAlertMonitor(config: .init(thresholdSeconds: 10, repeatInterval: 30))
        XCTAssertEqual(m.evaluate(currentPaceSecPerKm: 312, targetPaceSecPerKm: target, now: 0), .tooSlow)
    }
}
