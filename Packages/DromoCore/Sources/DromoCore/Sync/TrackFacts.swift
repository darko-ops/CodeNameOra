import Foundation

/// Facts about a recording as returned by the Global Track Table (Phase 1
/// `TrackFactsOut`). This is the candidate's objective values that the Phase-4
/// runtime engine selects over. Decodes straight from the server's snake_case JSON.
public struct TrackFacts: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var isrc: String?
    public var fingerprint: String?

    public var bpm: Double
    public var bpmConfidence: Double
    public var tempoOctaveFlag: AnalysisResult.OctaveFlag
    public var beatOffsetMs: Int?

    public var energy: Double?
    public var beatStrength: Double?
    public var driveScore: Double?

    public var durationMs: Int?
    public var analysisVersion: String
    public var confirmationCount: Int

    enum CodingKeys: String, CodingKey {
        case id, isrc, fingerprint, bpm
        case bpmConfidence = "bpm_confidence"
        case tempoOctaveFlag = "tempo_octave_flag"
        case beatOffsetMs = "beat_offset_ms"
        case energy
        case beatStrength = "beat_strength"
        case driveScore = "drive_score"
        case durationMs = "duration_ms"
        case analysisVersion = "analysis_version"
        case confirmationCount = "confirmation_count"
        // created_at / updated_at are present in the response but unused here.
    }

    public init(
        id: String, isrc: String? = nil, fingerprint: String? = nil,
        bpm: Double, bpmConfidence: Double, tempoOctaveFlag: AnalysisResult.OctaveFlag,
        beatOffsetMs: Int? = nil, energy: Double? = nil, beatStrength: Double? = nil,
        driveScore: Double? = nil, durationMs: Int? = nil,
        analysisVersion: String, confirmationCount: Int = 0
    ) {
        self.id = id
        self.isrc = isrc
        self.fingerprint = fingerprint
        self.bpm = bpm
        self.bpmConfidence = bpmConfidence
        self.tempoOctaveFlag = tempoOctaveFlag
        self.beatOffsetMs = beatOffsetMs
        self.energy = energy
        self.beatStrength = beatStrength
        self.driveScore = driveScore
        self.durationMs = durationMs
        self.analysisVersion = analysisVersion
        self.confirmationCount = confirmationCount
    }
}
