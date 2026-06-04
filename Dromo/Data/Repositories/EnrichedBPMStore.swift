import Foundation
import GRDB
import DromoCore

/// On-device cache of metadata-looked-up BPM (GetSongBPM), keyed by local track id.
/// Conforms to `BPMSink` so the enricher writes here; the live pool reads it back so
/// enriched tracks become tempo-matchable. Persisted, so the lookup runs only once.
struct EnrichedBPMStore: BPMSink {
    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    func store(bpm: Double, trackID: String) async {
        try? await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO bpm_enrichment (track_id, bpm, updated_at)
                VALUES (?, ?, strftime('%s','now'))
                ON CONFLICT(track_id) DO UPDATE SET bpm = excluded.bpm,
                                                    updated_at = excluded.updated_at
                """, arguments: [trackID, bpm])
        }
    }

    /// All cached BPMs, keyed by track id — used to fill the live pool.
    func all() async -> [String: Double] {
        (try? await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT track_id, bpm FROM bpm_enrichment")
                .reduce(into: [String: Double]()) { $0[$1["track_id"]] = $1["bpm"] }
        }) ?? [:]
    }
}
