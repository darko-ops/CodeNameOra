import Foundation

/// Royalty-free fallback catalog (Phase 6 Part B). Pre-tagged tracks spanning pace
/// bands, so a user whose own library is thin, slow, or unanalyzable still gets a
/// working paced session on day one.
///
/// Catalog tracks are ordinary `TrackFacts` — the Phase-4 engine treats them exactly
/// like any other candidate (NO special-casing in the selection math). `id` is
/// prefixed `catalog:` purely so the app can label provenance and resolve playback;
/// the engine never inspects it.
public enum FallbackCatalog {

    public static let tracks: [TrackFacts] = build()

    /// Tracks near a target BPM — backs an explicit "give me a 165 BPM run".
    public static func tracks(aroundBPM bpm: Double, tolerance: Double = 6) -> [TrackFacts] {
        tracks.filter { abs($0.bpm - bpm) <= tolerance }
              .sorted { abs($0.bpm - bpm) < abs($1.bpm - bpm) }
    }

    private static func build() -> [TrackFacts] {
        stride(from: 110, through: 190, by: 4).map { bpmInt -> TrackFacts in
            let bpm = Double(bpmInt)
            let energy: Double = min(1.0, 0.4 + (bpm - 110) / 160)
            let beatStrength = 0.7
            let tempoNorm: Double = max(0, min(1, (bpm - 90) / 90))
            let drive: Double = min(1, 0.5 * energy + 0.3 * beatStrength + 0.2 * tempoNorm)
            return TrackFacts(
                id: "catalog:\(bpmInt)",
                isrc: nil, fingerprint: "catalog-fp-\(bpmInt)",
                bpm: bpm, bpmConfidence: 0.95, tempoOctaveFlag: .none,
                beatOffsetMs: 0, energy: energy, beatStrength: beatStrength,
                driveScore: drive,
                durationMs: 200_000, analysisVersion: "catalog", confirmationCount: 0)
        }
    }
}
