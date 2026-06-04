import Foundation
import CoreLocation
import CoreMotion
import os
import DromoCore

private let paceLog = Logger(subsystem: "com.daed.dromo", category: "pace")

/// Live pace + cadence input for the loop (Phase 5). GPS speed → pace (sec/km) via
/// CoreLocation; cadence (steps/min) via CMPedometer (more responsive than GPS).
/// Emits a sample ~once per second; the loop's `CadenceSmoother` does the smoothing.
@MainActor
final class PaceCadenceSource: NSObject, CLLocationManagerDelegate {

    private let location = CLLocationManager()
    private let pedometer = CMPedometer()
    private var latestCadenceSPM = 0.0
    private var latestPaceSecPerKm = 0.0
    private var timer: Timer?

    /// Called ~1 Hz with the latest (cadence spm, pace sec/km).
    var onSample: (@Sendable (_ cadence: Double, _ paceSecPerKm: Double) -> Void)?

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        location.activityType = .fitness
    }

    func start() {
        location.requestWhenInUseAuthorization()
        location.startUpdatingLocation()
        paceLog.notice("started — location auth=\(self.location.authorizationStatus.rawValue), cadenceAvailable=\(CMPedometer.isCadenceAvailable())")

        if CMPedometer.isCadenceAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self, let cadence = data?.currentCadence else { return }
                let spm = cadence.doubleValue * 60   // steps/sec → steps/min
                Task { @MainActor in self.latestCadenceSPM = spm }
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emit() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        location.stopUpdatingLocation()
        pedometer.stopUpdates()
    }

    private var tick = 0
    private func emit() {
        tick += 1
        if tick % 5 == 0 {   // ~every 5s, avoid spam
            paceLog.notice("sample: pace=\(Int(self.latestPaceSecPerKm))s/km cadence=\(Int(self.latestCadenceSPM))spm")
        }
        onSample?(latestCadenceSPM, latestPaceSecPerKm)
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let speed = loc.speed   // m/s; negative when GPS hasn't resolved a valid speed
        // Reject negatives AND near-stationary drift (< 0.4 m/s ≈ slower than 41 min/km),
        // which otherwise produce absurd paces indoors (e.g. 200,000 s/km). Real outdoor
        // movement clears this gate.
        guard speed >= 0.4 else {
            paceLog.notice("gps speed too low (\(speed) m/s) — need outdoor movement for pace")
            return
        }
        let pace = 1_000.0 / speed
        Task { @MainActor in self.latestPaceSecPerKm = pace }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        paceLog.notice("location error: \(error.localizedDescription, privacy: .public)")
    }
}
