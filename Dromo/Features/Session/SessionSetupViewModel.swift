import Foundation
import DromoCore

/// Backs `SessionSetupView`. Holds the raw inputs (pace OR goal time) and derives
/// the canonical target pace (seconds/km) plus the `UserSettings` the engine needs.
@MainActor
final class SessionSetupViewModel: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case pace, goalTime
        var id: String { rawValue }
        var label: String { self == .pace ? "Pace" : "Goal time" }
    }

    @Published var mode: Mode = .pace
    @Published var useMetric = true

    // Pace mode (values are per selected unit).
    @Published var paceMinutes = 5
    @Published var paceSeconds = 30

    // Goal-time mode.
    @Published var distance: RaceDistance = .tenK
    @Published var goalHours = 0
    @Published var goalMinutes = 55
    @Published var goalSeconds = 0

    @Published var sensitivity: UserSettings.BPMSensitivity = .standard

    /// Optional distance goal for PACE mode (km; 0 = off). Goal-time mode already has a
    /// distance, so it's used automatically there.
    @Published var distanceGoalKm: Double = 0

    /// The run's distance goal in meters (for the finishing-line kick: the last 10%
    /// overrides fatigue softening and pushes), or nil when there's no goal.
    var targetDistanceMeters: Double? {
        switch mode {
        case .goalTime: return distance.meters                       // the race distance IS the goal
        case .pace:     return distanceGoalKm > 0 ? distanceGoalKm * 1_000 : nil
        }
    }

    /// Canonical target pace in seconds per kilometre.
    var targetPaceSecondsPerKm: Double {
        switch mode {
        case .pace:
            let perUnit = Double(paceMinutes * 60 + paceSeconds)
            return useMetric ? perUnit : perUnit / (PaceMath.metersPerMile / 1_000)
        case .goalTime:
            let goal = Double(goalHours * 3_600 + goalMinutes * 60 + goalSeconds)
            return PaceMath.paceSecondsPerKm(goalSeconds: goal, distanceMeters: distance.meters)
        }
    }

    var targetPaceDisplay: String {
        PaceMath.paceString(secondsPerKm: targetPaceSecondsPerKm, metric: useMetric)
    }

    var sensitivityDescription: String {
        switch sensitivity {
        case .conservative: return "Gentle BPM shifts — the music barely reacts."
        case .standard:     return "Balanced — music follows your pace smoothly."
        case .aggressive:   return "Strong reaction — music pushes hard off pace."
        }
    }

    var isValid: Bool { targetPaceSecondsPerKm > 60 && targetPaceSecondsPerKm < 1_200 }

    /// Prefill from a pace chosen elsewhere — the Sound tab's tempo ladder.
    ///
    /// Forces pace mode, since a goal time can't express "run at 5:15/km" without also
    /// asserting a distance the runner never picked. The seconds land on the nearest
    /// value the wheel can show, so what's displayed is what will be run.
    func apply(targetPaceSecondsPerKm pace: Double) {
        mode = .pace
        let perUnit = useMetric ? pace : pace * (PaceMath.metersPerMile / 1_000)
        let rounded = Int(perUnit.rounded())
        paceMinutes = min(max(rounded / 60, 2), 15)     // clamped to the wheel's range
        paceSeconds = min(max(rounded % 60, 0), 59)
    }

    func makeSettings() -> UserSettings {
        UserSettings(
            defaultPaceSecondsPerKm: targetPaceSecondsPerKm,
            bpmSensitivity: sensitivity,
            preferredProvider: .appleMusic,   // the service the app offers
            useMetric: useMetric
        )
    }
}
