import Foundation
import GRDB
import DromoCore

/// On-device cache of looked-up BPM, keyed by local track id, with the provenance of
/// each value. Conforms to `BPMSink` so the enrichment pass writes here; the live pool
/// reads it back so enriched tracks become tempo-matchable.
///
/// Writes are upgrade-only: a weaker source can never overwrite a stronger one, so
/// re-running a pass (or a Spotify answer arriving late) can't downgrade a tempo the
/// Global Track Table already measured.
struct EnrichedBPMStore: BPMSink {
    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    /// Legacy untagged write — kept for callers that have no provenance to offer.
    func store(bpm: Double, trackID: String) async {
        await store(BPMFinding(bpm: bpm, source: .getSongBPM), trackID: trackID)
    }

    func store(_ finding: BPMFinding, trackID: String) async {
        // The upgrade rule lives in `BPMFinding.supersedes`, so it can't drift apart
        // from the engine's view of which source to believe.
        guard finding.supersedes(await self.finding(trackID)) else { return }
        try? await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO bpm_enrichment (track_id, bpm, source, confidence, updated_at)
                VALUES (?, ?, ?, ?, strftime('%s','now'))
                ON CONFLICT(track_id) DO UPDATE SET bpm = excluded.bpm,
                                                    source = excluded.source,
                                                    confidence = excluded.confidence,
                                                    updated_at = excluded.updated_at
                """, arguments: [trackID, finding.bpm, finding.source.rawValue, finding.confidence])
        }
    }

    /// All cached BPMs, keyed by track id — used to fill the live pool.
    func all() async -> [String: Double] {
        (try? await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT track_id, bpm FROM bpm_enrichment")
                .reduce(into: [String: Double]()) { $0[$1["track_id"]] = $1["bpm"] }
        }) ?? [:]
    }

    /// Cached value WITH provenance — lets the UI explain where a tempo came from.
    func finding(_ trackID: String) async -> BPMFinding? {
        try? await dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT bpm, source, confidence FROM bpm_enrichment WHERE track_id = ?",
                arguments: [trackID]) else { return nil }
            let source = BPMSource(rawValue: row["source"] ?? "") ?? .getSongBPM
            return BPMFinding(bpm: row["bpm"], source: source, confidence: row["confidence"])
        }
    }

    /// How many cached tempos came from each source — the honest breakdown behind
    /// the coverage number.
    func countsBySource() async -> [BPMSource: Int] {
        (try? await dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT source, COUNT(*) AS n FROM bpm_enrichment GROUP BY source
                """).reduce(into: [BPMSource: Int]()) { counts, row in
                    if let source = BPMSource(rawValue: row["source"] ?? "") {
                        counts[source] = row["n"]
                    }
                }
        }) ?? [:]
    }
}

/// Persists what the background pass has already tried, so it resumes across launches
/// rather than re-querying the same tracks forever.
struct GRDBEnrichmentLedger: EnrichmentLedger {
    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    func attempt(for trackID: String) async -> EnrichmentAttempt? {
        try? await dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT attempts, last_attempt_at, resolved FROM enrichment_attempts
                WHERE track_id = ?
                """, arguments: [trackID]) else { return nil }
            return EnrichmentAttempt(
                trackID: trackID,
                attempts: row["attempts"],
                lastAttemptAt: Date(timeIntervalSince1970: row["last_attempt_at"]),
                resolved: (row["resolved"] as Int) == 1)
        }
    }

    func record(_ attempt: EnrichmentAttempt) async {
        try? await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO enrichment_attempts (track_id, attempts, last_attempt_at, resolved)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(track_id) DO UPDATE SET attempts = excluded.attempts,
                                                    last_attempt_at = excluded.last_attempt_at,
                                                    resolved = excluded.resolved
                """, arguments: [attempt.trackID, attempt.attempts,
                                 attempt.lastAttemptAt.timeIntervalSince1970,
                                 attempt.resolved ? 1 : 0])
        }
    }
}
