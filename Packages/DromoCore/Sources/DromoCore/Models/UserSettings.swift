import Foundation

/// User-configurable engine + playback parameters (Section 4.1).
public struct UserSettings: Codable, Equatable {
    public var defaultPaceSecondsPerKm: Double    // 360 = 6:00/km
    public var bpmSensitivity: BPMSensitivity
    public var preferredProvider: Track.MusicProvider
    public var useMetric: Bool
    public var minBPM: Double                     // floor, default 110
    public var maxBPM: Double                     // ceiling, default 180
    public var crossfadeDurationSeconds: Double   // default 4.0
    public var minTrackPlaySeconds: Double        // default 60.0

    public enum BPMSensitivity: String, Codable {
        case conservative   // ±10s/km = ±2 BPM
        case standard       // ±10s/km = ±4 BPM  (default)
        case aggressive     // ±10s/km = ±8 BPM
    }

    public init(
        defaultPaceSecondsPerKm: Double = 360.0,
        bpmSensitivity: BPMSensitivity = .standard,
        preferredProvider: Track.MusicProvider = .appleMusic,
        useMetric: Bool = true,
        minBPM: Double = 110,
        maxBPM: Double = 180,
        crossfadeDurationSeconds: Double = 4.0,
        minTrackPlaySeconds: Double = 60.0
    ) {
        self.defaultPaceSecondsPerKm = defaultPaceSecondsPerKm
        self.bpmSensitivity = bpmSensitivity
        self.preferredProvider = preferredProvider
        self.useMetric = useMetric
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.crossfadeDurationSeconds = crossfadeDurationSeconds
        self.minTrackPlaySeconds = minTrackPlaySeconds
    }

    public static let `default` = UserSettings()
}
