import Foundation
import CoreLocation

/// Real GPS pace source (Section 5.1 / Phase 1). Wraps `CLLocationManager`,
/// streams fitness-grade fixes, and forwards speed + coordinate as a
/// `PaceReading`. Accuracy filtering happens downstream in `PaceEngine` /
/// `GPSValidator`.
final class LocationManager: NSObject, PaceSource, CLLocationManagerDelegate {

    var onReading: ((PaceReading) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        // Background updates require an Always authorization.
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let speed = max(0, location.speed)   // m/s; negative when invalid
        onReading?(PaceReading(
            speedMetersPerSecond: speed,
            coordinate: location.coordinate,
            accuracyMeters: location.horizontalAccuracy
        ))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are ignored; the engine keeps the last good pace.
    }
}
