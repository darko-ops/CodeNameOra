import CoreLocation

/// GPS accuracy filtering (Section 5.1 / 15).
enum GPSValidator {
    static func isUsable(_ location: CLLocation, maxAccuracyMeters: Double = 20) -> Bool {
        location.horizontalAccuracy > 0 && location.horizontalAccuracy <= maxAccuracyMeters
    }
}
