import Foundation

/// Tops up a thin candidate pool with fallback-catalog tracks near the target
/// cadence (Phase 6 Part B "automatic backfill when BYO coverage is thin"). The
/// merged pool is just `[TrackFacts]` — the engine doesn't know or care which tracks
/// came from the catalog.
public enum CatalogBackfill {

    public static func augment(
        userPool: [TrackFacts],
        targetCadence: Double,
        catalog: [TrackFacts] = FallbackCatalog.tracks,
        minCandidatesNearTarget: Int = 3,
        band: Double = 10
    ) -> [TrackFacts] {
        let near = userPool.filter { abs($0.bpm - targetCadence) <= band }
        guard near.count < minCandidatesNearTarget else { return userPool }

        let needed = minCandidatesNearTarget - near.count
        let existing = Set(userPool.map(\.id))
        let fill = catalog
            .filter { abs($0.bpm - targetCadence) <= band && !existing.contains($0.id) }
            .sorted { abs($0.bpm - targetCadence) < abs($1.bpm - targetCadence) }
            .prefix(needed)
        return userPool + fill
    }
}
