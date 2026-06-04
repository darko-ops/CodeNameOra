import Foundation
import GRDB
import DromoCore

/// GRDB-backed local cache of Global Track Table facts — so a second session needs
/// no network (Phase 3 local cache). Conforms to DromoCore's `TrackFactsCache`, the
/// abstraction the sync coordinator depends on.
struct GRDBTrackFactsCache: TrackFactsCache {

    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    func get(_ key: IdentityKey) async -> TrackFacts? {
        try? await dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM track_facts
                WHERE (:isrc IS NOT NULL AND isrc = :isrc)
                   OR (:fp   IS NOT NULL AND fingerprint = :fp)
                LIMIT 1
                """, arguments: ["isrc": key.isrc, "fp": key.fingerprint])
            return row.map(Self.facts(from:))
        }
    }

    func put(_ facts: TrackFacts) async {
        try? await dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO track_facts
                  (id, isrc, fingerprint, bpm, bpm_confidence, tempo_octave_flag,
                   beat_offset_ms, energy, beat_strength, drive_score, duration_ms,
                   analysis_version, confirmation_count, cached_at)
                VALUES
                  (:id, :isrc, :fp, :bpm, :conf, :flag, :offset, :energy, :strength,
                   :drive, :dur, :ver, :conf_count, strftime('%s','now'))
                """, arguments: [
                    "id": facts.id, "isrc": facts.isrc, "fp": facts.fingerprint,
                    "bpm": facts.bpm, "conf": facts.bpmConfidence,
                    "flag": facts.tempoOctaveFlag.rawValue, "offset": facts.beatOffsetMs,
                    "energy": facts.energy, "strength": facts.beatStrength,
                    "drive": facts.driveScore, "dur": facts.durationMs,
                    "ver": facts.analysisVersion, "conf_count": facts.confirmationCount,
                ])
        }
    }

    func all() async -> [TrackFacts] {
        (try? await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM track_facts").map(Self.facts(from:))
        }) ?? []
    }

    private static func facts(from row: Row) -> TrackFacts {
        TrackFacts(
            id: row["id"],
            isrc: row["isrc"], fingerprint: row["fingerprint"],
            bpm: row["bpm"], bpmConfidence: row["bpm_confidence"],
            tempoOctaveFlag: AnalysisResult.OctaveFlag(rawValue: row["tempo_octave_flag"] ?? "none") ?? .none,
            beatOffsetMs: row["beat_offset_ms"],
            energy: row["energy"], beatStrength: row["beat_strength"], driveScore: row["drive_score"],
            durationMs: row["duration_ms"],
            analysisVersion: row["analysis_version"], confirmationCount: row["confirmation_count"])
    }
}
