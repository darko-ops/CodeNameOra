import Foundation

/// What the engine knows about a track's learned effectiveness: the estimate AND how
/// much evidence stands behind it.
///
/// The count is the load-bearing part. A single play is one runner on one day — hills,
/// traffic lights, a phone call — and letting that flip the ranking would make the
/// "DJ that learns you" feel random instead of attentive. Carrying observations lets
/// the engine trust the signal in proportion to the evidence, and lets a never-played
/// track be recognised as unknown rather than average.
public struct LearnedEffectiveness: Sendable, Equatable {

    /// 0…1, where 0.5 is neutral (this track neither helps nor hurts).
    public let value: Double
    /// How many finalized plays produced this estimate, in this mode.
    public let observations: Int

    public init(value: Double, observations: Int) {
        self.value = min(1, max(0, value))
        self.observations = max(0, observations)
    }

    /// Never played in this mode — the cold-start case exploration exists to fix.
    public static let unknown = LearnedEffectiveness(value: 0.5, observations: 0)

    /// A value with enough evidence behind it to act on at full weight. For callers
    /// (and tests) that mean "treat this as earned" without modelling a history.
    public static func trusted(_ value: Double) -> LearnedEffectiveness {
        LearnedEffectiveness(value: value, observations: Int.max)
    }

    /// How far to believe this estimate: 0 at no evidence, 1 once `minObservations`
    /// plays back it. Ramped rather than switched, so the engine's behaviour doesn't
    /// lurch on the run that happens to cross the threshold.
    public func trust(minObservations: Int) -> Double {
        guard minObservations > 0 else { return 1 }
        if observations >= minObservations { return 1 }
        return Double(observations) / Double(minObservations)
    }

    public var isUnplayed: Bool { observations == 0 }
}
