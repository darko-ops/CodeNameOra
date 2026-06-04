import Foundation
import CoreLocation
@testable import DromoCore

// MARK: - Track factory

func makeTrack(_ id: String, bpm: Double) -> Track {
    Track(
        id: id,
        title: "Track \(id)",
        artist: "Artist",
        bpm: bpm,
        energyLevel: 0.5,
        durationSeconds: 200,
        provider: .appleMusic
    )
}

// MARK: - CLLocation factory

/// Builds a CLLocation with a known speed (m/s) and horizontal accuracy (m).
func makeLocation(
    speed: CLLocationSpeed,
    accuracy: CLLocationAccuracy,
    timestamp: Date = Date()
) -> CLLocation {
    CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
        altitude: 0,
        horizontalAccuracy: accuracy,
        verticalAccuracy: 5,
        course: 0,
        speed: speed,
        timestamp: timestamp
    )
}

// MARK: - Spy crossfader

/// Records crossfade calls so tests can assert on transitions.
final class SpyCrossfader: TrackTransitioning {
    private(set) var crossfadeCallCount = 0
    private(set) var lastTrack: Track?

    func crossfade(to track: Track) async {
        crossfadeCallCount += 1
        lastTrack = track
    }
}

// MARK: - Mutable clock

/// A controllable clock for deterministic time-based tests.
final class MutableClock {
    var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.current = start
    }
    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
    var now: () -> Date { { self.current } }
}
