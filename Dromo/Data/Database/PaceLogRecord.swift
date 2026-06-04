import Foundation
import GRDB

/// GRDB row for the `pace_logs` table (Section 4.2). `id` autoincrements.
struct PaceLogRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "pace_logs"

    var id: Int64?
    var session_id: String
    var timestamp: Double
    var pace_sec_per_km: Double
    var target_pace_sec_per_km: Double
    var bpm_playing: Double
    var gap_seconds: Double
    var accuracy_meters: Double?
    var latitude: Double?
    var longitude: Double?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
