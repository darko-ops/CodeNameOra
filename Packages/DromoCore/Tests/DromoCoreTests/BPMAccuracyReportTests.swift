import XCTest
@testable import DromoCore

/// Tests the *measurement instrument* (Phase 7 metric math + verdict logic) with
/// synthetic true/detected pairs. This does NOT measure real BPM accuracy — that
/// needs a device + real owned music (the hardware-gated part of Phase 7).
final class BPMAccuracyReportTests: XCTestCase {

    private func row(_ id: String, true t: Double, detected d: Double, conf: Double = 0.9,
                     flag: AnalysisResult.OctaveFlag = .none, diff: String = "steady")
        -> GroundTruthResult {
        GroundTruthResult(trackID: id, trueBPM: t, difficulty: diff,
                          detectedBPM: d, confidence: conf, octaveFlag: flag)
    }

    func testExactAndOctaveMatchRates() {
        let rows = [
            row("a", true: 128, detected: 128),          // exact
            row("b", true: 174, detected: 87, flag: .double),  // octave error (recoverable)
            row("c", true: 140, detected: 120),          // genuinely wrong
        ]
        let r = BPMAccuracy.evaluate(rows)
        XCTAssertEqual(r.exactMatchRate, 1.0 / 3, accuracy: 0.01)
        XCTAssertEqual(r.octaveCorrectedMatchRate, 2.0 / 3, accuracy: 0.01, "a + b recover")
    }

    func testOctaveFlagRecall() {
        let rows = [
            row("flagged", true: 170, detected: 85, flag: .double),   // octave err, flagged ✓
            row("missed", true: 170, detected: 85, flag: .none),      // octave err, NOT flagged ✗
        ]
        let r = BPMAccuracy.evaluate(rows)
        XCTAssertEqual(r.octaveFlagRecall, 0.5, accuracy: 0.01)
    }

    func testConfidencePredictsErrorWhenLowConfIsWrong() {
        let rows = [
            row("h1", true: 128, detected: 128, conf: 0.9),
            row("h2", true: 150, detected: 150, conf: 0.9),
            row("l1", true: 140, detected: 100, conf: 0.2),   // low conf + wrong
        ]
        let r = BPMAccuracy.evaluate(rows)
        XCTAssertTrue(r.confidencePredictsError)
        XCTAssertEqual(r.highConfidenceErrorRate, 0, accuracy: 0.01)
        XCTAssertGreaterThan(r.lowConfidenceErrorRate, 0)
    }

    func testGreenVerdict() {
        // 19/20 octave-match, the one miss is low-confidence (so confidence predicts error).
        var rows: [GroundTruthResult] = (0..<17).map { row("h\($0)", true: 120, detected: 120, conf: 0.9) }
        rows.append(row("l-ok1", true: 130, detected: 130, conf: 0.3))
        rows.append(row("l-ok2", true: 160, detected: 160, conf: 0.3))
        rows.append(row("l-miss", true: 145, detected: 110, conf: 0.3))   // the lone miss, low conf
        let r = BPMAccuracy.evaluate(rows)
        XCTAssertEqual(r.octaveCorrectedMatchRate, 0.95, accuracy: 0.001)
        XCTAssertTrue(r.confidencePredictsError)
        XCTAssertEqual(r.verdict, .green)
    }

    func testRedWhenHighConfidenceOftenWrong() {
        let rows = [
            row("h1", true: 128, detected: 100, conf: 0.9),   // confident but wrong
            row("h2", true: 150, detected: 110, conf: 0.9),   // confident but wrong
            row("h3", true: 170, detected: 170, conf: 0.9),
        ]
        let r = BPMAccuracy.evaluate(rows)
        XCTAssertGreaterThan(r.highConfidenceErrorRate, 0.20)
        XCTAssertEqual(r.verdict, .red)
    }

    func testRedWhenMatchRateTooLow() {
        let rows = (0..<10).map { i in row("t\(i)", true: 120, detected: i < 4 ? 120 : 90) }  // 40% match
        let r = BPMAccuracy.evaluate(rows)
        XCTAssertLessThan(r.octaveCorrectedMatchRate, 0.70)
        XCTAssertEqual(r.verdict, .red)
    }

    func testErrorByDifficultyBreakdown() {
        let rows = [
            row("s1", true: 128, detected: 128, diff: "steady"),
            row("d1", true: 120, detected: 95, diff: "sparse"),   // wrong
            row("d2", true: 140, detected: 100, diff: "sparse"),  // wrong
        ]
        let r = BPMAccuracy.evaluate(rows)
        XCTAssertEqual(r.byDifficulty["steady"]?.octaveMatchRate, 1.0)
        XCTAssertEqual(r.byDifficulty["sparse"]?.octaveMatchRate, 0.0)
        XCTAssertEqual(r.byDifficulty["sparse"]?.count, 2)
    }
}
