import Foundation

/// Target pace derivation — settable three ways (Phase 5 acceptance): min/km,
/// min/mile, or a race goal time over a distance. Everything normalizes to
/// seconds-per-km, the unit the rest of the system speaks.
public enum PaceTarget {
    public static let metersPerMile = 1_609.344

    public static func fromPacePerKm(minutes: Int, seconds: Int) -> Double {
        Double(minutes * 60 + seconds)
    }

    public static func fromPacePerMile(minutes: Int, seconds: Int) -> Double {
        Double(minutes * 60 + seconds) / metersPerMile * 1_000
    }

    public static func fromGoalTime(distanceMeters: Double, goalSeconds: Double) -> Double {
        guard distanceMeters > 0 else { return 0 }
        return goalSeconds / (distanceMeters / 1_000)
    }
}

/// Maps a target pace to an expected running cadence (steps-per-minute), the signal
/// the Phase-4 engine controls on. This is a tunable heuristic (cadence rises gently
/// with speed), not physiology — calibrate `gainPerSecPerKm` against real runs.
public struct CadenceModel: Sendable, Equatable {
    public var baseCadence = 170.0
    public var referencePaceSecPerKm = 300.0   // 5:00/km ⇒ baseCadence
    public var gainPerSecPerKm = 0.05
    public var minCadence = 150.0
    public var maxCadence = 200.0

    public init() {}

    public func targetCadence(forPaceSecPerKm pace: Double) -> Double {
        let raw = baseCadence + (referencePaceSecPerKm - pace) * gainPerSecPerKm
        return min(maxCadence, max(minCadence, raw))
    }
}

/// Exponential-moving-average smoother for the noisy live cadence stream, with a
/// plausibility gate so a bad sample doesn't yank the average.
public struct CadenceSmoother: Sendable {
    public var alpha = 0.4
    public var minValid = 100.0
    public var maxValid = 230.0
    private var value: Double?

    public init() {}

    public mutating func add(_ raw: Double) -> Double {
        guard raw >= minValid, raw <= maxValid else { return value ?? raw }
        value = value.map { alpha * raw + (1 - alpha) * $0 } ?? raw
        return value ?? raw
    }

    public var current: Double? { value }
}
