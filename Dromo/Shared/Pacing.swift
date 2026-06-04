import SwiftUI
import DromoCore

// MARK: - Race distances (for the "goal time" setup mode)

enum RaceDistance: String, CaseIterable, Identifiable {
    case fiveK, tenK, half, marathon
    var id: String { rawValue }

    var meters: Double {
        switch self {
        case .fiveK:    return 5_000
        case .tenK:     return 10_000
        case .half:     return 21_097.5
        case .marathon: return 42_195
        }
    }

    var label: String {
        switch self {
        case .fiveK:    return "5K"
        case .tenK:     return "10K"
        case .half:     return "Half"
        case .marathon: return "Marathon"
        }
    }
}

// MARK: - Pace math

enum PaceMath {
    static let metersPerMile = 1_609.344

    /// Target pace (seconds per km) implied by a goal finish time over a distance.
    static func paceSecondsPerKm(goalSeconds: Double, distanceMeters: Double) -> Double {
        guard distanceMeters > 0 else { return 0 }
        return goalSeconds / (distanceMeters / 1_000)
    }

    /// Speed in m/s for a given pace — used to synthesize CLLocation in the simulator.
    static func metersPerSecond(fromPaceSecondsPerKm pace: Double) -> Double {
        pace > 0 ? 1_000 / pace : 0
    }

    /// "m:ss/km" or "m:ss/mi" depending on `metric`.
    static func paceString(secondsPerKm: Double, metric: Bool) -> String {
        guard secondsPerKm > 0 else { return metric ? "--:--/km" : "--:--/mi" }
        let perUnit = metric ? secondsPerKm : secondsPerKm * (metersPerMile / 1_000)
        let total = Int(perUnit.rounded())
        return String(format: "%d:%02d/%@", total / 60, total % 60, metric ? "km" : "mi")
    }

    /// Bare "m:ss" (no unit suffix).
    static func clock(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Run feedback (the "push / ease" signal)

enum RunFeedback {
    enum Status {
        case push      // behind target → speed up
        case onPace
        case ease      // ahead of target → slow down

        var label: String {
            switch self {
            case .push:   return "PUSH"
            case .onPace: return "ON PACE"
            case .ease:   return "EASE"
            }
        }

        var color: Color {
            switch self {
            case .push:   return .zonePeak      // orange-red
            case .onPace: return .zoneSteady    // green
            case .ease:   return .zoneWarmUp    // blue
            }
        }
    }

    /// Maps a pace gap (sec/km, positive = behind) to a coaching status.
    static func status(forGap gap: Double, tolerance: Double = 5) -> Status {
        if gap > tolerance { return .push }
        if gap < -tolerance { return .ease }
        return .onPace
    }

    /// Human description of the gap, e.g. "+12s/km behind" / "8s/km ahead".
    static func gapDescription(_ gap: Double) -> String {
        let s = Int(abs(gap).rounded())
        if s == 0 { return "right on target" }
        return gap > 0 ? "\(s)s/km behind" : "\(s)s/km ahead"
    }
}
