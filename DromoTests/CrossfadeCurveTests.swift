import XCTest
@testable import Dromo

/// Verifies the equal-power crossfade gain curve.
final class CrossfadeCurveTests: XCTestCase {

    func test_endpoints() {
        let start = CrossfadeCurve.gains(progress: 0)
        XCTAssertEqual(start.outgoing, 1, accuracy: 1e-9)
        XCTAssertEqual(start.incoming, 0, accuracy: 1e-9)

        let end = CrossfadeCurve.gains(progress: 1)
        XCTAssertEqual(end.outgoing, 0, accuracy: 1e-9)
        XCTAssertEqual(end.incoming, 1, accuracy: 1e-9)
    }

    func test_equalPowerInvariant() {
        for i in 0...10 {
            let g = CrossfadeCurve.gains(progress: Double(i) / 10)
            XCTAssertEqual(g.outgoing * g.outgoing + g.incoming * g.incoming, 1, accuracy: 1e-9,
                           "summed power must stay 1 across the fade")
        }
    }

    func test_clampsOutOfRange() {
        XCTAssertEqual(CrossfadeCurve.gains(progress: -1).outgoing, 1, accuracy: 1e-9)
        XCTAssertEqual(CrossfadeCurve.gains(progress: 2).incoming, 1, accuracy: 1e-9)
    }
}
