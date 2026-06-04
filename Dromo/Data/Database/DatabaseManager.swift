import Foundation
import GRDB

/// GRDB setup + schema migrations (Section 4.2 / Phase 1).
///
/// Opens a `DatabaseQueue` at Application Support/Dromo.sqlite and runs the schema
/// migration. Falls back to an in-memory database if the file can't be opened, so
/// the app never crashes on storage problems.
final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        let queue: DatabaseQueue
        do {
            let dir = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            queue = try DatabaseQueue(path: dir.appendingPathComponent("Dromo.sqlite").path)
        } catch {
            queue = try! DatabaseQueue()   // in-memory fallback
        }
        self.dbQueue = queue
        try? Self.migrator.migrate(queue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_schema") { db in
            try db.execute(sql: """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL,
                target_pace REAL NOT NULL,
                distance_meters REAL DEFAULT 0,
                elapsed_seconds INTEGER DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'active',
                exported_to_strava INTEGER DEFAULT 0,
                exported_to_health INTEGER DEFAULT 0,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            );

            CREATE TABLE tracks (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                bpm REAL NOT NULL,
                energy_level REAL DEFAULT 0.5,
                duration_seconds INTEGER NOT NULL,
                provider TEXT NOT NULL,
                bpm_verified INTEGER DEFAULT 0,
                last_updated REAL NOT NULL
            );

            CREATE TABLE pace_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL REFERENCES sessions(id),
                timestamp REAL NOT NULL,
                pace_sec_per_km REAL NOT NULL,
                target_pace_sec_per_km REAL NOT NULL,
                bpm_playing REAL NOT NULL,
                gap_seconds REAL NOT NULL,
                accuracy_meters REAL,
                latitude REAL,
                longitude REAL
            );

            CREATE TABLE track_plays (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL REFERENCES sessions(id),
                track_id TEXT NOT NULL REFERENCES tracks(id),
                started_at REAL NOT NULL,
                ended_at REAL,
                reason TEXT NOT NULL
            );

            CREATE INDEX idx_pace_logs_session ON pace_logs(session_id);
            CREATE INDEX idx_track_plays_session ON track_plays(session_id);
            CREATE INDEX idx_tracks_bpm ON tracks(bpm);
            """)
        }

        // Phase 3 — local cache of Global Track Table facts (lookup-first sync).
        // Identity is ISRC/fingerprint; facts only, no audio (ARCHITECTURE §4/§6).
        migrator.registerMigration("v2_track_facts") { db in
            try db.execute(sql: """
            CREATE TABLE track_facts (
                id TEXT PRIMARY KEY,
                isrc TEXT,
                fingerprint TEXT,
                bpm REAL NOT NULL,
                bpm_confidence REAL NOT NULL,
                tempo_octave_flag TEXT NOT NULL DEFAULT 'none',
                beat_offset_ms INTEGER,
                energy REAL,
                beat_strength REAL,
                drive_score REAL,
                duration_ms INTEGER,
                analysis_version TEXT NOT NULL,
                confirmation_count INTEGER NOT NULL DEFAULT 0,
                cached_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            );

            CREATE UNIQUE INDEX idx_track_facts_isrc ON track_facts(isrc) WHERE isrc IS NOT NULL;
            CREATE UNIQUE INDEX idx_track_facts_fp ON track_facts(fingerprint) WHERE fingerprint IS NOT NULL;
            """)
        }

        // Phase 6 A2 — PRIVATE per-user taste layer. Stays on device, NEVER uploaded
        // to the Global Track Table (ARCHITECTURE §5/§8). Separate store, by design.
        migrator.registerMigration("v3_user_preferences") { db in
            try db.execute(sql: """
            CREATE TABLE user_preferences (
                track_id TEXT PRIMARY KEY,
                weight REAL NOT NULL DEFAULT 0.5,
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            );
            """)
        }

        // BPM enrichment cache — metadata-looked-up BPM for DRM streaming tracks
        // (GetSongBPM), keyed by local track id. Looked up once, reused forever.
        migrator.registerMigration("v4_bpm_enrichment") { db in
            try db.execute(sql: """
            CREATE TABLE bpm_enrichment (
                track_id TEXT PRIMARY KEY,
                bpm REAL NOT NULL,
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            );
            """)
        }

        // User-set goals (You → Goals tab). Single row.
        migrator.registerMigration("v5_goals") { db in
            try db.execute(sql: """
            CREATE TABLE goals (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                weekly_sessions INTEGER NOT NULL DEFAULT 3,
                weekly_distance_km REAL NOT NULL DEFAULT 20,
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            );
            """)
        }

        // User-created playlists (Sound tab) — curated for specific sessions.
        migrator.registerMigration("v6_playlists") { db in
            try db.execute(sql: """
            CREATE TABLE playlists (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            );

            CREATE TABLE playlist_tracks (
                playlist_id TEXT NOT NULL REFERENCES playlists(id),
                track_id TEXT NOT NULL,
                position INTEGER NOT NULL,
                PRIMARY KEY (playlist_id, track_id)
            );

            CREATE INDEX idx_playlist_tracks_playlist ON playlist_tracks(playlist_id);
            """)
        }
        return migrator
    }
}
