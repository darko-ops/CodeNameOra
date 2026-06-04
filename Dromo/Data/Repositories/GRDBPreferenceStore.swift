import Foundation
import GRDB
import DromoCore

/// GRDB-backed private per-user taste store (Phase 6 A2). Conforms to DromoCore's
/// `PreferenceStoring`. This data is **on-device only** and is never sent to the
/// Global Track Table — the separation the architecture requires (§5/§8).
struct GRDBPreferenceStore: PreferenceStoring {

    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    func record(_ signal: SubjectiveSignal, trackID: String) async {
        let delta = Self.delta(for: signal)
        try? await dbQueue.write { db in
            let current = try Double.fetchOne(
                db, sql: "SELECT weight FROM user_preferences WHERE track_id = ?",
                arguments: [trackID]) ?? 0.5
            let updated = min(1, max(0, current + delta))
            try db.execute(sql: """
                INSERT INTO user_preferences (track_id, weight, updated_at)
                VALUES (?, ?, strftime('%s','now'))
                ON CONFLICT(track_id) DO UPDATE SET weight = excluded.weight,
                                                     updated_at = excluded.updated_at
                """, arguments: [trackID, updated])
        }
    }

    func weights() async -> [String: Double] {
        (try? await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT track_id, weight FROM user_preferences")
                .reduce(into: [String: Double]()) { $0[$1["track_id"]] = $1["weight"] }
        }) ?? [:]
    }

    private static func delta(for signal: SubjectiveSignal) -> Double {
        switch signal {
        case .liked: return 0.3
        case .kept: return 0.1
        case .skipped: return -0.3
        }
    }
}
