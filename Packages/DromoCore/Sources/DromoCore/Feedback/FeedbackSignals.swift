import Foundation

/// Objective feedback about a recording's *facts* (Phase 6 A1) — goes to the shared
/// Global Track Table. Distinct from `SubjectiveSignal` at the type level so the two
/// can never be conflated (ARCHITECTURE §5/§8: facts are global, taste is private).
public enum ObjectiveSignal: Sendable, Equatable {
    case confirmedOnTempo                      // the reading felt right
    case skippedAtTempo                        // skipped — possibly off-tempo
    case feltOffTempo(observedBPM: Double?)     // explicit "this isn't the tempo"

    /// Server signal string (`POST /v1/track/{id}/confirm`).
    public var serverSignal: String {
        switch self {
        case .confirmedOnTempo: return "confirm"
        case .skippedAtTempo, .feltOffTempo: return "off_tempo"
        }
    }

    public var observedBPM: Double? {
        if case let .feltOffTempo(bpm) = self { return bpm }
        return nil
    }
}

/// Subjective feedback about the user's *taste* (Phase 6 A2) — stays in the private
/// per-user layer and only ever influences selection as a soft weight. NEVER sent to
/// the global table.
public enum SubjectiveSignal: String, Sendable, Equatable {
    case liked, kept, skipped
}
