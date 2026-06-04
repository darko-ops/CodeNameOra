import XCTest
@testable import DromoCore

final class GapCalculatorTests: XCTestCase {

    func test_gap_whenBehindPace() {
        // Actual slower (higher sec/km) than target → positive gap.
        let gap = GapCalculator.gap(actualPaceSecondsPerKm: 400, targetPaceSecondsPerKm: 360)
        XCTAssertEqual(gap, 40, accuracy: 0.0001)
        XCTAssertGreaterThan(gap, 0)
    }

    func test_gap_whenAheadOfPace() {
        // Actual faster (lower sec/km) than target → negative gap.
        let gap = GapCalculator.gap(actualPaceSecondsPerKm: 330, targetPaceSecondsPerKm: 360)
        XCTAssertEqual(gap, -30, accuracy: 0.0001)
        XCTAssertLessThan(gap, 0)
    }

    func test_gap_whenExactlyOnPace() {
        let gap = GapCalculator.gap(actualPaceSecondsPerKm: 360, targetPaceSecondsPerKm: 360)
        XCTAssertEqual(gap, 0, accuracy: 0.0001)
    }
}
