import Foundation

/// Result of one key in a batch lookup — the key echoed back with its facts (or nil).
public struct BatchResult: Sendable, Equatable {
    public let key: IdentityKey
    public let facts: TrackFacts?

    public init(key: IdentityKey, facts: TrackFacts?) {
        self.key = key
        self.facts = facts
    }
}

/// The Global Track Table transport (Phase 1 server). Abstracted so the sync logic
/// is testable with a fake server, and so only identity keys + numeric results ever
/// cross it (ARCHITECTURE §4/§5 — no audio, no titles).
public protocol TrackTableAPI: Sendable {
    func lookup(_ key: IdentityKey) async throws -> TrackFacts?
    func batchLookup(_ keys: [IdentityKey]) async throws -> [BatchResult]
    func populate(_ result: AnalysisResult) async throws -> TrackFacts
    /// Objective feedback (Phase 6 A1): corroborate or correct a recording's facts.
    func confirm(trackID: String, signal: ObjectiveSignal, clientID: String) async throws -> TrackFacts?
}
