import Foundation
import HealthKit
import CoreLocation
import DromoCore

/// Saves a completed run to Apple Health as an `HKWorkout` with a GPS route
/// (Section 6.4). Uses `HKWorkoutBuilder` / `HKWorkoutRouteBuilder`.
///
/// Requires the HealthKit capability on the App ID + entitlement (a Phase 0
/// manual step). The framework compiles without it; authorization fails at
/// runtime until the capability is enabled.
final class HealthKitManager {

    enum HealthError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Health data isn't available on this device." }
    }

    private let store = HKHealthStore()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.unavailable }
        let toShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        try await store.requestAuthorization(toShare: toShare, read: [])
    }

    /// Saves the workout and its route. Returns nothing; throws on failure.
    func save(session: Session) async throws {
        try await requestAuthorization()

        let start = session.startedAt
        let end = session.endedAt ?? Date()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)

        if let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
           session.distanceMeters > 0 {
            let sample = HKCumulativeQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: session.distanceMeters),
                start: start,
                end: end
            )
            try await builder.addSamples([sample])
        }

        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()

        // Attach the GPS route, if we have one.
        let locations = session.actualPaces
            .filter { $0.latitude != 0 || $0.longitude != 0 }
            .map { log in
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: log.latitude, longitude: log.longitude),
                    altitude: 0,
                    horizontalAccuracy: log.accuracyMeters,
                    verticalAccuracy: log.accuracyMeters,
                    timestamp: log.timestamp
                )
            }

        if let workout, !locations.isEmpty {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await routeBuilder.insertRouteData(locations)
            try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
    }
}
