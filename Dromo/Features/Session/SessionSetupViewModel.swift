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

    func makeSettings() -> UserSettings {
        UserSettings(
            defaultPaceSecondsPerKm: targetPaceSecondsPerKm,
            bpmSensitivity: sensitivity,
            preferredProvider: .spotify,
            useMetric: useMetric
        )
    }
}
