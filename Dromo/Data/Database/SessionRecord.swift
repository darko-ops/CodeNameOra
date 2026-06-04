import Foundation
import GRDB

/// GRDB row for the `sessions` table (Section 4.2). Column names match the schema.
struct SessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sessions"

    var id: String
    var started_at: Double
    var ended_at: Double?
    var target_pace: Double
    var distance_meters: Double
    var elapsed_seconds: Int
    var status: String
    var exported_to_strava: Int
    var exported_to_health: Int
    var created_at: Double
}
