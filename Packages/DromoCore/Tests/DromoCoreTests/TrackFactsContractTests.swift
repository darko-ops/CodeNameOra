import XCTest
@testable import DromoCore

/// Locks the client↔server JSON contract: `TrackFacts` must decode the exact body
/// the Phase-1 server returns (captured from a live `GET /v1/track`), and an
/// `AnalysisResult` must encode to exactly what the server's `POST /v1/track` accepts.
final class TrackFactsContractTests: XCTestCase {

    func testDecodesLiveServerResponse() throws {
        // Verbatim from the running Phase-1 API (extra created_at/updated_at ignored).
        let json = """
        {"id":"e9d814f98276483ca0f75104e5746fa8","isrc":"USRC17607839","fingerprint":null,
         "bpm":174.0,"bpm_confidence":0.9,"tempo_octave_flag":"none","beat_offset_ms":null,
         "energy":null,"beat_strength":null,"drive_score":null,"duration_ms":null,
         "analysis_version":"vdsp-1","confirmation_count":0,
         "created_at":"2026-06-01T22:09:58.599420","updated_at":"2026-06-01T22:09:58.599424"}
        """.data(using: .utf8)!

        let facts = try JSONDecoder().decode(TrackFacts.self, from: json)
        XCTAssertEqual(facts.id, "e9d814f98276483ca0f75104e5746fa8")
        XCTAssertEqual(facts.isrc, "USRC17607839")
        XCTAssertNil(facts.fingerprint)
        XCTAssertEqual(facts.bpm, 174.0)
        XCTAssertEqual(facts.tempoOctaveFlag, .none)
        XCTAssertEqual(facts.confirmationCount, 0)
    }

    func testAnalysisResultEncodesToServerAcceptedBody() throws {
        let result = AnalysisResult(isrc: "USRC17607839", bpm: 174, bpmConfidence: 0.9,
                                    tempoOctaveFlag: .none, analysisVersion: "vdsp-1")
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(result)) as! [String: Any]
        // Server's TrackFactsIn requires these and forbids unknown fields.
        XCTAssertEqual(json["isrc"] as? String, "USRC17607839")
        XCTAssertEqual(json["bpm"] as? Double, 174)
        XCTAssertNotNil(json["bpm_confidence"])
        XCTAssertNotNil(json["analysis_version"])
        XCTAssertNil(json["audio"])
    }
}
