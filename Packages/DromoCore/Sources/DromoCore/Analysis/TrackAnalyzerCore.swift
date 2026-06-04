import Foundation

/// Combines tempo/feature extraction + fingerprinting into one `AnalysisResult`.
/// Pure (samples in, numbers out) — the platform layer (app target) feeds it decoded
/// PCM and attaches ISRC/duration. This is the boundary the legal rule protects: the
/// only thing leaving analysis is this numeric struct (ARCHITECTURE §4).
public struct TrackAnalyzerCore {

    /// Stamped onto every result so the server can selectively re-analyze later (§7).
    public static let analysisVersion = "vdsp-1"

    public var tempo = OnsetTempoAnalyzer()
    public var fingerprinter = ChromaFingerprinter()

    public init() {}

    public func analyze(
        samples: [Float],
        sampleRate: Double,
        isrc: String? = nil,
        durationMs: Int? = nil
    ) -> AnalysisResult? {
        guard let t = tempo.analyze(samples: samples, sampleRate: sampleRate) else { return nil }
        let fingerprint = fingerprinter.fingerprint(samples: samples, sampleRate: sampleRate)
        return AnalysisResult(
            isrc: isrc,
            fingerprint: fingerprint,
            bpm: t.bpm,
            bpmConfidence: t.confidence,
            tempoOctaveFlag: t.octaveFlag,
            beatOffsetMs: t.beatOffsetMs,
            energy: t.energy,
            beatStrength: t.beatStrength,
            driveScore: driveScore(energy: t.energy, beatStrength: t.beatStrength, bpm: t.bpm),
            durationMs: durationMs,
            analysisVersion: Self.analysisVersion
        )
    }

    /// Derived convenience metric for fast candidate ranking (§7 Tier-2): blends
    /// loudness, pulse prominence, and tempo into one 0–1 "drive" score.
    func driveScore(energy: Double, beatStrength: Double, bpm: Double) -> Double {
        let tempoNorm = max(0, min(1, (bpm - 90) / 90))   // ~90→0, ~180→1
        return max(0, min(1, 0.5 * energy + 0.3 * beatStrength + 0.2 * tempoNorm))
    }
}
