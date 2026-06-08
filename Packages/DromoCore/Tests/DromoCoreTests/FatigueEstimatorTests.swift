import XCTest
@testable import DromoCore

final class FatigueEstimatorTests: XCTestCase {

    func testFreshRunnerIsFullyFresh() {
        var f = FatigueEstimator()
        // A few early on-pace samples → no fatigue signal yet.
        for t in 0..<10 { f.ingest(now: Double(t), cadence: 170, gap: 0) }
        XCTAssertEqual(f.coefficient(now: 10), 1.0, accuracy: 0.0001)
    }

    func testIgnoresStandingSamples() {
        var f = FatigueEstimator()
        // cadence 0 (standing / no signal) must not look like a huge "behind" gap.
        for t in 0..<200 { f.ingest(now: Double(t), cadence: 0, gap: 170) }
        XCTAssertEqual(f.coefficient(now: 200), 1.0, accuracy: 0.0001)
    }

    func testProgressiveSlowdownLowersCoefficient() {
        var f = FatigueEstimator()
        // 0–60s steady at 172, then drifting down to ~160 by the end (a clear slowdown).
        for t in 0...60 { f.ingest(now: Double(t), cadence: 172, gap: 0) }
        for t in 61...240 {
            let cad = max(160, 172 - Double(t - 60) / 15.0)
            f.ingest(now: Double(t), cadence: cad, gap: 172 - cad)
        }
        XCTAssertLessThan(f.coefficient(now: 240), 1.0)
    }

    func testSustainedBehindLowersCoefficient() {
        var f = FatigueEstimator()
        // Steady cadence but consistently ~12 spm behind target for 2+ minutes.
        for t in 0...150 { f.ingest(now: Double(t), cadence: 158, gap: 12) }
        let c = f.coefficient(now: 150)
        XCTAssertLessThan(c, 1.0)
        XCTAssertGreaterThanOrEqual(c, f.config.floor)
    }

    func testLongDurationContributesFatigue() {
        var f = FatigueEstimator()
        // Steady, on pace, but 50 minutes in → duration alone softens things.
        // Sample sparsely (every 30s) to keep the test light; trend stays neutral.
        var t = 0.0
        while t <= 50 * 60 { f.ingest(now: t, cadence: 170, gap: 0); t += 30 }
        XCTAssertLessThan(f.coefficient(now: 50 * 60), 1.0)
    }

    func testNeverBelowFloor() {
        var f = FatigueEstimator()
        // Pile on every signal: long, slowing hard, far behind.
        for t in 0...300 {
            let cad = max(140, 175 - Double(t) / 5.0)
            f.ingest(now: Double(t) + 40 * 60, cadence: cad, gap: 175 - cad)
        }
        XCTAssertGreaterThanOrEqual(f.coefficient(now: 300 + 40 * 60), f.config.floor)
    }
}
