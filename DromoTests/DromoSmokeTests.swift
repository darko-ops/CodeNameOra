import XCTest
import DromoCore
@testable import Dromo

/// Phase 0 smoke tests — prove the app target builds and links DromoCore.
/// (The engine's own unit tests live in the DromoCore package.)
final class DromoSmokeTests: XCTestCase {
    func test_oraCoreIsLinked() {
        let settings = UserSettings.default
        XCTAssertGreaterThan(settings.maxBPM, settings.minBPM)
    }

    func test_paceCalculatorConversion() {
        XCTAssertEqual(PaceCalculator.secondsPerKm(fromSpeedMS: 5), 200, accuracy: 0.0001)
    }
}
