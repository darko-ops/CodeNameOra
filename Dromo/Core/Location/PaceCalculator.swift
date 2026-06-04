import Foundation

/// Pace conversion + smoothing helpers (Section 5.1).
enum PaceCalculator {
    /// Converts a speed in m/s to pace in seconds per kilometer.
    static func secondsPerKm(fromSpeedMS speed: Double) -> Double {
        speed > 0 ? 1000.0 / speed : 0
    }
}
