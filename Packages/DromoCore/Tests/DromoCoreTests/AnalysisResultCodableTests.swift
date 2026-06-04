import XCTest
@testable import DromoCore

final class AnalysisResultCodableTests: XCTestCase {

    /// Encodes to exactly the snake_case keys the Phase-1 server expects on
    /// `POST /v1/track`, so Phase 3 can upload without a translation layer.
    func testEncodesToServerSchemaKeys() throws {
        let result = AnalysisResult(
            isrc: "USRC17607839", fingerprint: "0123456789abcdef",
            bpm: 174.2, bpmConfidence: 0.9, tempoOctaveFlag: .double,
            beatOffsetMs: 120, energy: 0.8, beatStrength: 0.7, driveScore: 0.77,
            durationMs: 210_000, analysisVersion: "vdsp-1")

        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        for key in ["isrc", "fingerprint", "bpm", "bpm_confidence", "tempo_octave_flag",
                    "beat_offset_ms", "energy", "beat_strength", "drive_score",
                    "duration_ms", "analysis_version"] {
            XCTAssertNotNil(json[key], "missing server key \(key)")
        }
        XCTAssertEqual(json["tempo_octave_flag"] as? String, "double")
        XCTAssertNil(json["audio"], "no audio field may ever exist")
    }

    func testRoundTrips() throws {
        let r = AnalysisResult(fingerprint: "abc", bpm: 128, bpmConfidence: 0.5,
                               tempoOctaveFlag: .none, analysisVersion: "vdsp-1")
        let back = try JSONDecoder().decode(AnalysisResult.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(r, back)
    }

    func testDriveScoreInRange() {
        let core = TrackAnalyzerCore()
        XCTAssertEqual(core.driveScore(energy: 1, beatStrength: 1, bpm: 200), 1, accuracy: 0.0001)
        XCTAssertEqual(core.driveScore(energy: 0, beatStrength: 0, bpm: 60), 0, accuracy: 0.0001)
    }
}
