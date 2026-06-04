import Foundation
import GRDB

/// GRDB row for the `tracks` table — the cached BPM index (Section 4.2).
struct TrackRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tracks"

    var id: String
    var title: String
    var artist: String
    var bpm: Double
    var energy_level: Double
    var duration_seconds: Int
    var provider: String
    var bpm_verified: Int
    var last_updated: Double
}
