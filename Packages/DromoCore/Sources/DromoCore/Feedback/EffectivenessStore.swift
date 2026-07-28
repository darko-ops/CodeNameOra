import Foundation

/// Private, per-user store of LEARNED behavioral effectiveness: for each (track, mode),
/// how reliably that track moved this runner the right way (0…1, 0.5 = neutral/unknown).
///
/// This is demonstrated behavior, not stated taste — but like the taste layer it is
/// on-device only and NEVER uploaded to the Global Track Table (ARCHITECTURE §5/§8):
/// it's a fact about *this runner's response*, not about the recording. Behind a
/// protocol so it's swappable/testable and kept separate from `TrackTableAPI` by type.
public protocol EffectivenessStoring: Sendable {
    /// Fold a finalized response into the (track, mode) estimate.
    func record(_ response: TrackResponse) async
    /// Learned effectiveness for one mode: trackID → 0…1. Unknown tracks are omitted
    /// (the engine treats a missing entry as neutral).
    func effectiveness(for mode: PaceMode) async -> [String: Double]
    /// The same estimates WITH their observation counts, which is what the engine needs
    /// to weight a signal by the evidence behind it rather than acting on one play.
    func learned(for mode: PaceMode) async -> [String: LearnedEffectiveness]
}

// NOTE: deliberately NO default implementation of `learned(for:)`. A protocol-extension
// default here silently wins overload resolution against an actor's own isolated
// method, so every store would have reported `Int.max` observations — every estimate
// fully trusted from its first play, exactly the bug the counts exist to prevent.
// Requiring conformers to implement it makes that failure a compile error instead.

/// In-memory implementation for previews/tests. Applies the EMA learner per (track, mode).
public actor InMemoryEffectivenessStore: EffectivenessStoring {
    private var byMode: [PaceMode: [String: LearnedEffectiveness]] = [:]
    private let learner: EffectivenessLearner

    public init(learner: EffectivenessLearner = .init()) { self.learner = learner }

    public func record(_ response: TrackResponse) {
        let prev = byMode[response.mode]?[response.trackID]
        let updated = learner.updated(previous: prev?.value, reward: response.reward)
        byMode[response.mode, default: [:]][response.trackID] = LearnedEffectiveness(
            value: updated, observations: (prev?.observations ?? 0) + 1)
    }

    public func effectiveness(for mode: PaceMode) -> [String: Double] {
        (byMode[mode] ?? [:]).mapValues(\.value)
    }

    public func learned(for mode: PaceMode) -> [String: LearnedEffectiveness] {
        byMode[mode] ?? [:]
    }
}
