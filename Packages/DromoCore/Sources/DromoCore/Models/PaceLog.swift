import Foundation

/// Per-second snapshot of a running session (Section 4.1).
public struct PaceLog: Codable, Equatable {
    public let timestamp: Date
    public let paceSecondsPerKm: Double        // actual pace at this moment
    public let targetPaceSecondsPerKm: Double
    public let bpmPlaying: Double              // what was playing
    public let gapSeconds: Double              // delta
    public let accuracyMeters: Double          // GPS horizontal accuracy
    public let latitude: Double
    public let longitude: Double

    public init(
        timestamp: Date,
        paceSecondsPerKm: Double,
        targetPaceSecondsPerKm: Double,
        bpmPlaying: Double,
        gapSeconds: Double,
        accuracyMeters: Double,
        latitude: Double,
        longitude: Double
    ) {
        self.timestamp = timestamp
        self.paceSecondsPerKm = paceSecondsPerKm
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
        self.bpmPlaying = bpmPlaying
        self.gapSeconds = gapSeconds
        self.accuracyMeters = accuracyMeters
        self.latitude = latitude
        self.longitude = longitude
    }
}
