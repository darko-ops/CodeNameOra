import CoreLocation

/// One pace reading delivered to the session loop.
struct PaceReading {
    let speedMetersPerSecond: Double
    /// Real coordinate when available (GPS); nil for the simulator source.
    let coordinate: CLLocationCoordinate2D?
    let accuracyMeters: Double
}

/// Abstraction over "where pace comes from" so `SessionController` is identical
/// for real GPS and the simulator. Implementers may deliver readings from any
/// thread; the consumer bridges to the main actor.
protocol PaceSource: AnyObject {
    var onReading: ((PaceReading) -> Void)? { get set }
    func start()
    func stop()
}
