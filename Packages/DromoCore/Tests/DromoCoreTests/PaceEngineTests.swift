import XCTest
import CoreLocation
@testable import DromoCore

final class PaceEngineTests: XCTestCase {

    func test_rollingAverage_withFiveReadings_returnsCorrectMean() async {
        let engine = PaceEngine()
        // Speeds chosen to yield round paces (1000 / speed):
        // 2.0→500, 2.5→400, 4.0→250, 5.0→200, 8.0→125  (mean = 295.0)
        let speeds: [CLLocationSpeed] = [2.0, 2.5, 4.0, 5.0, 8.0]
        let base = Date(timeIntervalSince1970: 1_000_000)
        for (i, speed) in speeds.enumerated() {
            let loc = makeLocation(speed: speed, accuracy: 5, timestamp: base.addingTimeInterval(Double(i)))
            await engine.ingestLocation(loc)
        }
        let pace = await engine.currentPaceSecondsPerKm
        XCTAssertEqual(pace, 295.0, accuracy: 0.0001)
    }

    func test_ingestLocation_withPoorAccuracy_isRejected() async {
        let engine = PaceEngine()
        let accepted = await engine.ingestLocation(makeLocation(speed: 3.0, accuracy: 50))  // > 20m
        XCTAssertFalse(accepted)
        let pace = await engine.currentPaceSecondsPerKm
        XCTAssertEqual(pace, 0, accuracy: 0.0001)
    }

    func test_ingestLocation_stationaryNoise_isRejected() async {
        let engine = PaceEngine()
        let accepted = await engine.ingestLocation(makeLocation(speed: 0.3, accuracy: 5))  // < 0.5 m/s
        XCTAssertFalse(accepted)
        let pace = await engine.currentPaceSecondsPerKm
        XCTAssertEqual(pace, 0, accuracy: 0.0001)
    }

    func test_rollingWindow_keepsOnlyLastTenReadings() async {
        let engine = PaceEngine()
        let base = Date(timeIntervalSince1970: 1_000_000)
        // 10 readings at 4.0 m/s (pace 250), then 2 at 2.0 m/s (pace 500).
        // Window holds the last 10: eight 250s + two 500s → (8*250 + 2*500)/10 = 300.
        for i in 0..<10 {
            await engine.ingestLocation(makeLocation(speed: 4.0, accuracy: 5, timestamp: base.addingTimeInterval(Double(i))))
        }
        for i in 10..<12 {
            await engine.ingestLocation(makeLocation(speed: 2.0, accuracy: 5, timestamp: base.addingTimeInterval(Double(i))))
        }
        let pace = await engine.currentPaceSecondsPerKm
        XCTAssertEqual(pace, 300.0, accuracy: 0.0001)
    }

    func test_currentGap_behindTarget_returnsPositive() async {
        let engine = PaceEngine()
        await engine.setTargetPace(360)                 // 6:00/km
        await engine.ingestLocation(makeLocation(speed: 2.5, accuracy: 5))  // pace 400 → slower
        let gap = await engine.currentGap()
        XCTAssertGreaterThan(gap, 0)
        XCTAssertEqual(gap, 40, accuracy: 0.0001)
    }

    func test_currentGap_aheadOfTarget_returnsNegative() async {
        let engine = PaceEngine()
        await engine.setTargetPace(360)                 // 6:00/km
        await engine.ingestLocation(makeLocation(speed: 4.0, accuracy: 5))  // pace 250 → faster
        let gap = await engine.currentGap()
        XCTAssertLessThan(gap, 0)
        XCTAssertEqual(gap, -110, accuracy: 0.0001)
    }
}
