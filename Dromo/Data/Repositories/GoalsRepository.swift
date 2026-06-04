import Foundation
import GRDB

/// The user's weekly goals (You → Goals).
struct WeeklyGoals: Equatable {
    var weeklySessions: Int = 3
    var weeklyDistanceKm: Double = 20
}

/// This week's progress toward those goals, from recorded sessions.
struct WeekProgress: Equatable {
    var sessions: Int = 0
    var distanceKm: Double = 0
}

/// Persists goals (single row) and computes current-week progress from `sessions`.
struct GoalsRepository {
    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    func load() async -> WeeklyGoals {
        (try? await dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT weekly_sessions, weekly_distance_km FROM goals WHERE id = 1")
            else { return WeeklyGoals() }
            return WeeklyGoals(weeklySessions: row["weekly_sessions"],
                               weeklyDistanceKm: row["weekly_distance_km"])
        }) ?? WeeklyGoals()
    }

    func save(_ goals: WeeklyGoals) async {
        try? await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO goals (id, weekly_sessions, weekly_distance_km, updated_at)
                VALUES (1, ?, ?, strftime('%s','now'))
                ON CONFLICT(id) DO UPDATE SET weekly_sessions = excluded.weekly_sessions,
                                              weekly_distance_km = excluded.weekly_distance_km,
                                              updated_at = excluded.updated_at
                """, arguments: [goals.weeklySessions, goals.weeklyDistanceKm])
        }
    }

    func weekProgress(now: Date = Date()) async -> WeekProgress {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let ts = weekStart.timeIntervalSince1970
        return (try? await dbQueue.read { db in
            let sessions = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM sessions WHERE started_at >= ?", arguments: [ts]) ?? 0
            let meters = try Double.fetchOne(
                db, sql: "SELECT COALESCE(SUM(distance_meters), 0) FROM sessions WHERE started_at >= ?",
                arguments: [ts]) ?? 0
            return WeekProgress(sessions: sessions, distanceKm: meters / 1_000)
        }) ?? WeekProgress()
    }
}
