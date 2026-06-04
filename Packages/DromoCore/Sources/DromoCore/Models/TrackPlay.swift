import Foundation

/// Records which track played, when, and why it was chosen (Section 4.1).
public struct TrackPlay: Codable, Equatable {
    public let track: Track
    public let startedAt: Date
    public var endedAt: Date?
    public let reasonForSelection: SelectionReason

    public enum SelectionReason: String, Codable {
        case initial, paceIncrease, paceDecrease, trackEnded, userSkip
    }

    public init(
        track: Track,
        startedAt: Date,
        endedAt: Date? = nil,
        reasonForSelection: SelectionReason
    ) {
        self.track = track
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.reasonForSelection = reasonForSelection
    }
}
