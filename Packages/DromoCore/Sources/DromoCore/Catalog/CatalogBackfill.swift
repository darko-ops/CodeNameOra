import Foundation

/// Merges the fallback catalog into the runner's own pool. The merged pool is just
/// `[TrackFacts]` — the engine doesn't know or care which tracks came from the
/// catalog, beyond the equal-fit tiebreak carried in `SessionPool.origins`.
public enum CatalogBackfill {

    /// How much catalog to admit.
    public enum Policy: Sendable, Equatable {
        /// Catalog-first: the whole catalog joins the pool, so EVERY cadence a session
        /// can ask for has a candidate on day one, whatever shape the library is in.
        /// The runner's own tracks still win at equal fit (`SelectionConfig.catalogPenalty`).
        case union
        /// Legacy top-up: catalog tracks are added only where the runner's own coverage
        /// near the target is thin. Keeps a well-covered library entirely their own.
        case backfillWhenThin(minCandidatesNearTarget: Int = 3, band: Double = 10)
    }

    /// Build the session pool, carrying each track's origin alongside the facts.
    /// This is the Phase-1 entry point; `augment` remains for callers that only want
    /// the flat array.
    public static func merge(
        userPool: [TrackFacts],
        targetCadence: Double,
        catalog: [TrackFacts] = FallbackCatalog.tracks,
        policy: Policy = .union
    ) -> SessionPool {
        let existing = Set(userPool.map(\.id))
        let admitted: [TrackFacts]
        switch policy {
        case .union:
            admitted = catalog.filter { !existing.contains($0.id) }
        case let .backfillWhenThin(minNear, band):
            admitted = Array(topUp(userPool: userPool, targetCadence: targetCadence,
                                   catalog: catalog, minNear: minNear, band: band))
        }
        var origins = Dictionary(userPool.map { ($0.id, TrackOrigin.library) },
                                 uniquingKeysWith: { a, _ in a })
        for track in admitted { origins[track.id] = .catalog }
        return SessionPool(facts: userPool + admitted, origins: origins)
    }

    public static func augment(
        userPool: [TrackFacts],
        targetCadence: Double,
        catalog: [TrackFacts] = FallbackCatalog.tracks,
        minCandidatesNearTarget: Int = 3,
        band: Double = 10
    ) -> [TrackFacts] {
        userPool + topUp(userPool: userPool, targetCadence: targetCadence, catalog: catalog,
                         minNear: minCandidatesNearTarget, band: band)
    }

    /// The tracks a thin band needs: nearest-to-target first, never a duplicate.
    private static func topUp(
        userPool: [TrackFacts], targetCadence: Double, catalog: [TrackFacts],
        minNear: Int, band: Double
    ) -> [TrackFacts] {
        let near = userPool.filter { abs($0.bpm - targetCadence) <= band }
        guard near.count < minNear else { return [] }

        let existing = Set(userPool.map(\.id))
        return catalog
            .filter { abs($0.bpm - targetCadence) <= band && !existing.contains($0.id) }
            .sorted { abs($0.bpm - targetCadence) < abs($1.bpm - targetCadence) }
            .prefix(minNear - near.count)
            .map { $0 }
    }
}
