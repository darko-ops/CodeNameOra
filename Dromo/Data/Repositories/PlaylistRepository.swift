import Foundation
import GRDB

/// A user-created playlist: id + name + ordered track ids (the tracks are resolved
/// from the live library for display).
struct UserPlaylistRecord: Identifiable, Equatable {
    let id: String
    let name: String
    let trackIDs: [String]
}

/// Persists user-created playlists (Sound tab).
struct PlaylistRepository {
    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    func create(name: String, trackIDs: [String]) async {
        let id = UUID().uuidString
        try? await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO playlists (id, name) VALUES (?, ?)",
                           arguments: [id, name])
            for (index, trackID) in trackIDs.enumerated() {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position)
                    VALUES (?, ?, ?)
                    """, arguments: [id, trackID, index])
            }
        }
    }

    func all() async -> [UserPlaylistRecord] {
        (try? await dbQueue.read { db -> [UserPlaylistRecord] in
            let rows = try Row.fetchAll(db, sql: "SELECT id, name FROM playlists ORDER BY created_at DESC")
            return try rows.map { row in
                let id: String = row["id"]
                let trackIDs = try String.fetchAll(
                    db, sql: "SELECT track_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position",
                    arguments: [id])
                return UserPlaylistRecord(id: id, name: row["name"], trackIDs: trackIDs)
            }
        }) ?? []
    }

    func rename(id: String, name: String) async {
        try? await dbQueue.write { db in
            try db.execute(sql: "UPDATE playlists SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    func delete(id: String) async {
        try? await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM playlist_tracks WHERE playlist_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM playlists WHERE id = ?", arguments: [id])
        }
    }
}
