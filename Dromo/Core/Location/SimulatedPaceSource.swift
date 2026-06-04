import Foundation

/// Simulator stand-in for GPS: emits a reading every second at whatever pace the
/// on-screen control currently holds, so the full loop runs without CoreLocation.
final class SimulatedPaceSource: PaceSource {

    var onReading: ((PaceReading) -> Void)?

    private let paceProvider: () -> Double   // current target/actual pace (sec/km)
    private var task: Task<Void, Never>?

    init(paceProvider: @escaping () -> Double) {
        self.paceProvider = paceProvider
    }

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                let speed = PaceMath.metersPerSecond(fromPaceSecondsPerKm: self.paceProvider())
                self.onReading?(PaceReading(
                    speedMetersPerSecond: speed,
                    coordinate: nil,
                    accuracyMeters: 5
                ))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
