import Foundation

/// Domain model for a single run (Section 4.1).
public struct Session: Identifiable, Codable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public let targetPace: Double         // seconds per kilometer
    public var actualPaces: [PaceLog]     // 1-per-second log
    public var tracks: [TrackPlay]        // what played when
    public var distanceMeters: Double
    public var elapsedSeconds: Int
    public var status: SessionStatus

    public enum SessionStatus: String, Codable {
        case active, paused, completed, abandoned
    }

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        targetPace: Double,
        actualPaces: [PaceLog] = [],
        tracks: [TrackPlay] = [],
        distanceMeters: Double = 0,
        elapsedSeconds: Int = 0,
        status: SessionStatus = .active
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetPace = targetPace
        self.actualPaces = actualPaces
        self.tracks = tracks
        self.distanceMeters = distanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.status = status
    }
}
