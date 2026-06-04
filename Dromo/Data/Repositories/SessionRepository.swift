import Foundation
import GRDB
import DromoCore

/// Lightweight row for the Library list (no per-second data loaded).
struct SessionSummary: Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date?
    let distanceMeters: Double
    let elapsedSeconds: Int
    let targetPace: Double

    var averagePaceSecondsPerKm: Double {
        elapsedSeconds > 0 && distanceMeters > 0
            ? Double(elapsedSeconds) / (distanceMeters / 1_000) : 0
    }
}

/// Persists and queries runs (Section 3 / Phase 1), mapping DromoCore `Session`
/// values to/from the GRDB schema.
struct SessionRepository {
    private let dbQueue = DatabaseManager.shared.dbQueue

    // MARK: - Save

    func save(_ session: Session) async throws {
        try await dbQueue.write { db in
            try SessionRecord(
                id: session.id.uuidString,
                started_at: session.startedAt.timeIntervalSince1970,
                ended_at: session.endedAt?.timeIntervalSince1970,
                target_pace: session.targetPace,
                distance_meters: session.distanceMeters,
                elapsed_seconds: session.elapsedSeconds,
                status: session.status.rawValue,
                exported_to_strava: 0,
                exported_to_health: 0,
                created_at: Date().timeIntervalSince1970
            ).insert(db, onConflict: .replace)

            for log in session.actualPaces {
                var row = PaceLogRecord(
                    id: nil,
                    session_id: session.id.uuidString,
                    timestamp: log.timestamp.timeIntervalSince1970,
                    pace_sec_per_km: log.paceSecondsPerKm,
                    target_pace_sec_per_km: log.targetPaceSecondsPerKm,
                    bpm_playing: log.bpmPlaying,
                    gap_seconds: log.gapSeconds,
                    accuracy_meters: log.accuracyMeters,
                    latitude: log.latitude,
                    longitude: log.longitude
                )
                try row.insert(db)
            }

            for play in session.tracks {
                try TrackRecord(
                    id: play.track.id,
                    title: play.track.title,
                    artist: play.track.artist,
                    bpm: play.track.bpm,
                    energy_level: play.track.energyLevel,
                    duration_seconds: play.track.durationSeconds,
                    provider: play.track.provider.rawValue,
                    bpm_verified: 1,
                    last_updated: Date().timeIntervalSince1970
                ).insert(db, onConflict: .replace)

                var playRow = TrackPlayRecord(
                    id: nil,
                    session_id: session.id.uuidString,
                    track_id: play.track.id,
                    started_at: play.startedAt.timeIntervalSince1970,
                    ended_at: play.endedAt?.timeIntervalSince1970,
                    reason: play.reasonForSelection.rawValue
                )
                try playRow.insert(db)
            }
        }
    }

    // MARK: - Read

    func summaries() async throws -> [SessionSummary] {
        try await dbQueue.read { db in
            try SessionRecord
                .order(Column("started_at").desc)
                .fetchAll(db)
                .map { row in
                    SessionSummary(
                        id: row.id,
                        startedAt: Date(timeIntervalSince1970: row.started_at),
                        endedAt: row.ended_at.map(Date.init(timeIntervalSince1970:)),
                        distanceMeters: row.distance_meters,
                        elapsedSeconds: row.elapsed_seconds,
                        targetPace: row.target_pace
                    )
                }
        }
    }

    /// Reconstructs a session with its per-second pace log (for the detail chart).
    func fullSession(id: String) async throws -> Session? {
        try await dbQueue.read { db in
            guard let row = try SessionRecord.fetchOne(db, key: id) else { return nil }
            let logs = try PaceLogRecord
                .filter(Column("session_id") == id)
                .order(Column("timestamp"))
                .fetchAll(db)

            let paceLogs = logs.map { log in
                PaceLog(
                    timestamp: Date(timeIntervalSince1970: log.timestamp),
                    paceSecondsPerKm: log.pace_sec_per_km,
                    targetPaceSecondsPerKm: log.target_pace_sec_per_km,
                    bpmPlaying: log.bpm_playing,
                    gapSeconds: log.gap_seconds,
                    accuracyMeters: log.accuracy_meters ?? 0,
                    latitude: log.latitude ?? 0,
                    longitude: log.longitude ?? 0
                )
            }

            return Session(
                id: UUID(uuidString: row.id) ?? UUID(),
                startedAt: Date(timeIntervalSince1970: row.started_at),
                endedAt: row.ended_at.map(Date.init(timeIntervalSince1970:)),
                targetPace: row.target_pace,
                actualPaces: paceLogs,
                tracks: [],
                distanceMeters: row.distance_meters,
                elapsedSeconds: row.elapsed_seconds,
                status: Session.SessionStatus(rawValue: row.status) ?? .completed
            )
        }
    }

    // MARK: - Delete

    func delete(id: String) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM pace_logs WHERE session_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM track_plays WHERE session_id = ?", arguments: [id])
            _ = try SessionRecord.deleteOne(db, key: id)
        }
    }
}
