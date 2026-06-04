import Foundation

/// Private per-user taste store (Phase 6 A2). Produces soft selection weights the
/// Phase-4 engine consumes. The app backs this with on-device storage; this lives
/// behind a protocol so it's swappable and testable, and so the type system keeps it
/// entirely separate from the global `TrackTableAPI`.
public protocol PreferenceStoring: Sendable {
    func record(_ signal: SubjectiveSignal, trackID: String) async
    func weights() async -> [String: Double]
}

/// In-memory implementation for previews/tests. Weight starts neutral (0.5) and
/// drifts with taste signals, clamped to 0…1.
public actor InMemoryPreferenceStore: PreferenceStoring {
    private var weightByID: [String: Double] = [:]

    public init() {}

    public func record(_ signal: SubjectiveSignal, trackID: String) {
        let current = weightByID[trackID] ?? 0.5
        weightByID[trackID] = min(1, max(0, current + Self.delta(for: signal)))
    }

    public func weights() -> [String: Double] { weightByID }

    static func delta(for signal: SubjectiveSignal) -> Double {
        switch signal {
        case .liked: return 0.3
        case .kept: return 0.1
        case .skipped: return -0.3
        }
    }
}
