import Foundation
import GRDB

/// GRDB row for the `track_plays` table (Section 4.2). `id` autoincrements.
struct TrackPlayRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "track_plays"

    var id: Int64?
    var session_id: String
    var track_id: String
    var started_at: Double
    var ended_at: Double?
    var reason: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
