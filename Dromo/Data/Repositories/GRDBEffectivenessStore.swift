import Foundation
import GRDB
import DromoCore

/// GRDB-backed store of LEARNED behavioral effectiveness per (track, pace mode).
/// Conforms to DromoCore's `EffectivenessStoring`. Like the taste layer, this is
/// **on-device only** and is never sent to the Global Track Table — it's a fact about
/// this runner's response, not about the recording (ARCHITECTURE §5/§8).
struct GRDBEffectivenessStore: EffectivenessStoring {

    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }
    private let learner = EffectivenessLearner()

    func record(_ response: TrackResponse) async {
        let learner = self.learner
        try? await dbQueue.write { db in
            let prev = try Double.fetchOne(
                db,
                sql: "SELECT effectiveness FROM track_effectiveness WHERE track_id = ? AND mode = ?",
                arguments: [response.trackID, response.mode.rawValue])
            let updated = learner.updated(previous: prev, reward: response.reward)
            try db.execute(sql: """
                INSERT INTO track_effectiveness (track_id, mode, effectiveness, samples, updated_at)
                VALUES (?, ?, ?, 1, strftime('%s','now'))
                ON CONFLICT(track_id, mode) DO UPDATE SET
                    effectiveness = excluded.effectiveness,
                    samples = track_effectiveness.samples + 1,
                    updated_at = excluded.updated_at
                """, arguments: [response.trackID, response.mode.rawValue, updated])
        }
    }

    func effectiveness(for mode: PaceMode) async -> [String: Double] {
        (try? await dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT track_id, effectiveness FROM track_effectiveness WHERE mode = ?",
                arguments: [mode.rawValue])
                .reduce(into: [String: Double]()) { $0[$1["track_id"]] = $1["effectiveness"] }
        }) ?? [:]
    }

    /// Estimates WITH their observation counts. The count is what lets the engine
    /// weight a signal by the evidence behind it — one play nudges the ranking, several
    /// can flip it — so it must come from the stored `samples`, never be assumed.
    func learned(for mode: PaceMode) async -> [String: LearnedEffectiveness] {
        (try? await dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT track_id, effectiveness, samples FROM track_effectiveness WHERE mode = ?",
                arguments: [mode.rawValue])
                .reduce(into: [String: LearnedEffectiveness]()) { out, row in
                    out[row["track_id"]] = LearnedEffectiveness(
                        value: row["effectiveness"], observations: row["samples"])
                }
        }) ?? [:]
    }

    /// Erase every learned response. Local and complete — this data never left the
    /// device, so there is nothing else to revoke.
    func reset() async {
        try? await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM track_effectiveness")
        }
    }

    /// All modes at once — used to prime the live loop at session start.
    func allByMode() async -> [PaceMode: [String: LearnedEffectiveness]] {
        var result: [PaceMode: [String: LearnedEffectiveness]] = [:]
        for mode in PaceMode.allCases {
            result[mode] = await learned(for: mode)
        }
        return result
    }
}
