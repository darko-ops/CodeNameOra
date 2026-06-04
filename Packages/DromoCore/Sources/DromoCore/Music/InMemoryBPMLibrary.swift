import Foundation

/// A simple in-memory BPM library used for previews and tests, and as a base
/// for the cached index the app layer populates from MusicKit / Spotify.
public actor InMemoryBPMLibrary: BPMLibraryProviding {
    private var allTracks: [Track]

    public init(tracks: [Track] = []) {
        self.allTracks = tracks
    }

    public func setTracks(_ tracks: [Track]) {
        self.allTracks = tracks
    }

    public func add(_ track: Track) {
        allTracks.append(track)
    }

    public func tracks(nearBPM bpm: Double, tolerance: Double) async -> [Track] {
        allTracks.filter { abs($0.bpm - bpm) <= tolerance }
    }
}
