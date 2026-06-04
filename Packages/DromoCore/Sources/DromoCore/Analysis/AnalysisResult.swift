import Foundation

/// The objective analysis of one recording — the on-device product of Phase 2, and
/// the exact payload uploaded to the Global Track Table (Phase 1 / ARCHITECTURE §7).
///
/// Numbers + identity only; NEVER audio. `CodingKeys` are snake_case so this encodes
/// straight onto the `POST /v1/track` body with no translation layer.
public struct AnalysisResult: Codable, Equatable, Sendable {

    /// Half/double-time ambiguity marker (§7). The detector records the ambiguity;
    /// the runtime engine (Phase 4) resolves it against the user's actual cadence.
    /// `.half` ⇒ true tempo may be `bpm / 2`; `.double` ⇒ may be `bpm * 2`.
    public enum OctaveFlag: String, Codable, Sendable {
        case none, half, double, ambiguous
    }

    // Identity (§6) — at least one is set before upload.
    public var isrc: String?
    public var fingerprint: String?

    // Tier 1 — essential
    public var bpm: Double
    public var bpmConfidence: Double
    public var tempoOctaveFlag: OctaveFlag
    public var beatOffsetMs: Int?

    // Tier 2 — high value for pacing
    public var energy: Double?
    public var beatStrength: Double?
    public var driveScore: Double?

    // Tier 3
    public var durationMs: Int?

    // Bookkeeping
    public var analysisVersion: String

    enum CodingKeys: String, CodingKey {
        case isrc, fingerprint, bpm
        case bpmConfidence = "bpm_confidence"
        case tempoOctaveFlag = "tempo_octave_flag"
        case beatOffsetMs = "beat_offset_ms"
        case energy
        case beatStrength = "beat_strength"
        case driveScore = "drive_score"
        case durationMs = "duration_ms"
        case analysisVersion = "analysis_version"
    }

    public init(
        isrc: String? = nil,
        fingerprint: String? = nil,
        bpm: Double,
        bpmConfidence: Double,
        tempoOctaveFlag: OctaveFlag,
        beatOffsetMs: Int? = nil,
        energy: Double? = nil,
        beatStrength: Double? = nil,
        driveScore: Double? = nil,
        durationMs: Int? = nil,
        analysisVersion: String
    ) {
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
    }
}
