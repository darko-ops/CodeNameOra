import Foundation
import GRDB
import DromoCore

/// A track in the "most played" ranking.
struct TopTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let plays: Int
}

/// The "You" dashboard stats, computed from persisted runs.
struct DashboardStats: Equatable {
    var momentumWeeks: Int = 0   // weekly streak
    var totalUses: Int = 0       // sessions logged
    var totalListens: Int = 0    // songs played across all runs
    var topTracks: [TopTrack] = []
}

/// Queries the run history for the dashboard (sessions / track_plays / tracks tables).
struct StatsRepository {
    private let dbQueue = DatabaseManager.shared.dbQueue

    func load(now: Date = Date()) async throws -> DashboardStats {
        try await dbQueue.read { db in
            let totalUses = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions") ?? 0
            let totalListens = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM track_plays") ?? 0

            let topRows = try Row.fetchAll(db, sql: """
                SELECT tp.track_id AS id, t.title AS title, t.artist AS artist, COUNT(*) AS plays
                FROM track_plays tp
                JOIN tracks t ON t.id = tp.track_id
                GROUP BY tp.track_id
                ORDER BY plays DESC, t.title ASC
                LIMIT 5
                """)
            let topTracks = topRows.map {
                TopTrack(id: $0["id"], title: $0["title"], artist: $0["artist"], plays: $0["plays"])
            }

            let startTimes = try Double.fetchAll(db, sql: "SELECT started_at FROM sessions")
            let momentum = StreakCalculator.weeklyStreak(
                sessionDates: startTimes.map { Date(timeIntervalSince1970: $0) }, now: now)

            return DashboardStats(momentumWeeks: momentum, totalUses: totalUses,
                                  totalListens: totalListens, topTracks: topTracks)
        }
    }
}
