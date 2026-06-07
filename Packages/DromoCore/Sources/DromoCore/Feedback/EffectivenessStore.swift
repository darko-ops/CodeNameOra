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
}

/// In-memory implementation for previews/tests. Applies the EMA learner per (track, mode).
public actor InMemoryEffectivenessStore: EffectivenessStoring {
    private var byMode: [PaceMode: [String: Double]] = [:]
    private let learner: EffectivenessLearner

    public init(learner: EffectivenessLearner = .init()) { self.learner = learner }

    public func record(_ response: TrackResponse) {
        let prev = byMode[response.mode]?[response.trackID]
        let updated = learner.updated(previous: prev, reward: response.reward)
        byMode[response.mode, default: [:]][response.trackID] = updated
    }

    public func effectiveness(for mode: PaceMode) -> [String: Double] {
        byMode[mode] ?? [:]
    }
}
