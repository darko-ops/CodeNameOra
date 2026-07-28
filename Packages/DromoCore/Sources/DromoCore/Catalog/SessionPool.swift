import Foundation

/// Where a candidate came from. The engine stays provenance-blind in its *math* —
/// a catalog track is scored on the same objective facts as any other — but the
/// product promise is "your music, when we know it; ours, so the run always works".
/// So origin is carried BESIDE the facts (never inside `TrackFacts`, which is the
/// server's wire contract) and used only as a tiebreak at equal fit.
public enum TrackOrigin: String, Sendable, Equatable, Codable {
    /// The runner's own music.
    case library
    /// Dromo's pre-tagged fallback catalog — the day-one guarantee.
    case catalog
}

/// The candidate pool for one session: the facts the engine selects over, plus the
/// origin of each, so the UI can say "from your library" and selection can prefer
/// the runner's own music when nothing objective separates two tracks.
///
/// Unknown ids resolve to `.library`: anything the app injected without declaring an
/// origin is the runner's, and treating it as such never demotes their own music.
public struct SessionPool: Sendable, Equatable {

    public let facts: [TrackFacts]
    public let origins: [String: TrackOrigin]

    public init(facts: [TrackFacts], origins: [String: TrackOrigin] = [:]) {
        self.facts = facts
        self.origins = origins
    }

    /// A pool that is entirely the runner's own music.
    public static func library(_ facts: [TrackFacts]) -> SessionPool {
        SessionPool(facts: facts,
                    origins: Dictionary(facts.map { ($0.id, TrackOrigin.library) },
                                        uniquingKeysWith: { a, _ in a }))
    }

    public func origin(of id: String) -> TrackOrigin { origins[id] ?? .library }

    public var libraryTracks: [TrackFacts] { facts.filter { origin(of: $0.id) == .library } }
    public var catalogTracks: [TrackFacts] { facts.filter { origin(of: $0.id) == .catalog } }

    /// The BPM span the pool can actually pace to (tracks with a known tempo). Empty
    /// when nothing is tagged — which is exactly the state the catalog exists to fix.
    public var bpmSpan: ClosedRange<Double>? {
        let known = facts.map(\.bpm).filter { $0 > 0 }
        guard let lo = known.min(), let hi = known.max() else { return nil }
        return lo...hi
    }

    /// Does the pool have a candidate within `band` of every cadence a session might
    /// ask for? The day-one guarantee in one assertion.
    public func spans(_ range: ClosedRange<Double>, band: Double = 6) -> Bool {
        let known = facts.map(\.bpm).filter { $0 > 0 }
        guard !known.isEmpty else { return false }
        return stride(from: range.lowerBound, through: range.upperBound, by: band)
            .allSatisfy { target in known.contains { abs($0 - target) <= band } }
    }
}

/// The pool IS its candidates — it just remembers where each came from. Collection
/// conformance keeps every existing `pool.first { … }` / `pool.filter { … }` call
/// site working, so provenance is additive rather than a migration.
extension SessionPool: RandomAccessCollection {
    public var startIndex: Int { facts.startIndex }
    public var endIndex: Int { facts.endIndex }
    public subscript(position: Int) -> TrackFacts { facts[position] }
}
