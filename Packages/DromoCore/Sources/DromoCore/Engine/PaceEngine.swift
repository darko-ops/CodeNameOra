import Foundation
import CoreLocation

/// The heart of the app: ingests GPS readings, maintains a smoothed current
/// pace, and reports the gap against the target pace (Section 5.1).
///
/// Implemented as an `actor` for thread safety — GPS callbacks arrive on the
/// location delegate queue while the UI reads state from the main actor.
public actor PaceEngine {

    // MARK: - Configuration
    private let updateInterval: TimeInterval = 1.0      // 1Hz GPS reads
    private let smoothingWindow: Int = 10               // rolling average seconds
    private let minAccuracyMeters: Double = 20.0        // reject poor GPS
    private let minSpeedMetersPerSecond: Double = 0.5   // filter stationary noise

    // MARK: - State
    /// Stores smoothed pace readings (seconds/km) with their timestamps.
    private var rawReadings: [(pace: Double, timestamp: Date)] = []
    private var targetPaceSecondsPerKm: Double = 360.0  // 6:00/km default
    public private(set) var currentPaceSecondsPerKm: Double = 0
    public private(set) var isActive: Bool = false

    public init() {}

    // MARK: - Public interface
    public func setTargetPace(_ pace: Double) {
        targetPaceSecondsPerKm = pace
    }

    public func setActive(_ active: Bool) {
        isActive = active
    }

    @discardableResult
    public func ingestLocation(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy <= minAccuracyMeters,
              location.horizontalAccuracy > 0 else { return false }

        // CLLocation.speed is in m/s. Convert to sec/km.
        let speedMS = location.speed
        guard speedMS > minSpeedMetersPerSecond else { return false }  // filter stationary noise

        let paceSecPerKm = 1000.0 / speedMS
        rawReadings.append((paceSecPerKm, location.timestamp))

        // Keep only the last N readings for the rolling window.
        if rawReadings.count > smoothingWindow {
            rawReadings.removeFirst(rawReadings.count - smoothingWindow)
        }

        currentPaceSecondsPerKm = rollingAveragePace()
        return true
    }

    /// Positive = running slower than target (need to speed up).
    /// Negative = running faster than target (need to slow down).
    public func currentGap() -> Double {
        GapCalculator.gap(
            actualPaceSecondsPerKm: currentPaceSecondsPerKm,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm
        )
    }

    public var target: Double { targetPaceSecondsPerKm }

    public func reset() {
        rawReadings.removeAll()
        currentPaceSecondsPerKm = 0
    }

    // MARK: - Private
    private func rollingAveragePace() -> Double {
        guard !rawReadings.isEmpty else { return 0 }
        let sum = rawReadings.reduce(0.0) { $0 + $1.pace }
        return sum / Double(rawReadings.count)
    }
}
