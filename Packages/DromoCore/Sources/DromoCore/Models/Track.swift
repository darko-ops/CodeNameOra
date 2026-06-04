import Foundation

/// Unified track model shared across music providers (Section 4.1).
public struct Track: Identifiable, Codable, Equatable {
    public let id: String                 // platform-specific ID
    public let title: String
    public let artist: String
    public let bpm: Double                // beats per minute
    public let energyLevel: Double        // 0.0 – 1.0 (from Spotify or derived)
    public let durationSeconds: Int
    public let provider: MusicProvider

    public enum MusicProvider: String, Codable {
        case appleMusic, spotify
    }

    public init(
        id: String,
        title: String,
        artist: String,
        bpm: Double,
        energyLevel: Double,
        durationSeconds: Int,
        provider: MusicProvider
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.energyLevel = energyLevel
        self.durationSeconds = durationSeconds
        self.provider = provider
    }
}
