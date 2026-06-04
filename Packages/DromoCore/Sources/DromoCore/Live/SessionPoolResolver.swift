import Foundation

/// One track in the user's library, reduced to what pool-building needs: a local
/// playback id, an optional identity (ISRC/fingerprint), and any provider-exposed
/// BPM (§9 fallback when on-device analysis isn't possible).
public struct LibraryEntry: Sendable, Equatable {
    public let localID: String
    public let identity: IdentityKey?
    public let providerBPM: Double?
    public let energy: Double?
    public let durationMs: Int?

    public init(localID: String, identity: IdentityKey? = nil,
                providerBPM: Double? = nil, energy: Double? = nil, durationMs: Int? = nil) {
        self.localID = localID
        self.identity = identity
        self.providerBPM = providerBPM
        self.energy = energy
        self.durationMs = durationMs
    }
}

/// Builds the live session's candidate pool the architecture-correct way and bridges
/// it to runtime playback ids. Layering (best source wins), per ARCHITECTURE §2/§6/§9:
///   1. **Global Track Table facts** (lookup-first, analyze-on-miss via Phase 3),
///   2. else **provider-exposed BPM** (the §9 fallback for DRM/streaming),
///   3. plus **fallback-catalog backfill** for any thin BPM band (Phase 6).
///
/// `initialPool` returns instantly (provider + catalog) so a run starts with zero
/// wait; `resolvedPool` runs the Phase-3 sync in the background and returns the
/// upgraded pool, which the live loop swaps in via `updateCandidates`.
public actor SessionPoolResolver {
    private let coordinator: LibrarySyncCoordinator
    private let cache: TrackFactsCache
    private let catalog: [TrackFacts]

    public init(coordinator: LibrarySyncCoordinator, cache: TrackFactsCache,
                catalog: [TrackFacts] = FallbackCatalog.tracks) {
        self.coordinator = coordinator
        self.cache = cache
        self.catalog = catalog
    }

    /// Instant pool: provider-known BPM + catalog backfill. Playback can start now.
    /// Static — needs no network/coordinator, so the UI can call it before resolution.
    public static func initialPool(entries: [LibraryEntry], targetCadence: Double,
                                   catalog: [TrackFacts] = FallbackCatalog.tracks) -> [TrackFacts] {
        let seed = entries.compactMap { providerFacts($0) }
        return CatalogBackfill.augment(userPool: seed, targetCadence: targetCadence, catalog: catalog)
    }

    /// Resolve via the Global Track Table (lookup-first; misses analyzed in the
    /// background, populating the table + cache), then build the upgraded pool with
    /// resolved facts mapped back to local playback ids.
    public func resolvedPool(entries: [LibraryEntry], targetCadence: Double) async -> [TrackFacts] {
        let items = entries.compactMap { entry -> SyncItem? in
            guard let identity = entry.identity, identity.isValid else { return nil }
            return SyncItem(localID: entry.localID, key: identity)
        }
        if !items.isEmpty { _ = await coordinator.resolveLibrary(items) }

        var pool: [TrackFacts] = []
        for entry in entries {
            if let identity = entry.identity, let facts = await cache.get(identity) {
                pool.append(remap(facts, toLocalID: entry.localID))   // Track Table wins
            } else if let provider = Self.providerFacts(entry) {
                pool.append(provider)                                  // §9 fallback
            }
        }
        return CatalogBackfill.augment(userPool: pool, targetCadence: targetCadence, catalog: catalog)
    }

    // MARK: - Private

    private static func providerFacts(_ entry: LibraryEntry) -> TrackFacts? {
        // Include the track even when BPM is unknown (bpm 0): it's a real, PLAYABLE
        // song. Without a tempo it just can't be tempo-matched yet — but the engine
        // can still play it, which beats an empty/unplayable pool. A known provider
        // BPM gets normal confidence; unknown gets 0 so any real reading wins later.
        let bpm = entry.providerBPM ?? 0
        return TrackFacts(
            id: entry.localID, bpm: bpm, bpmConfidence: bpm > 0 ? 0.7 : 0,
            tempoOctaveFlag: .none, energy: entry.energy, beatStrength: 0.6,
            durationMs: entry.durationMs, analysisVersion: "provider")
    }

    /// Re-key resolved facts to the local playback id so the loop can play them.
    private func remap(_ f: TrackFacts, toLocalID id: String) -> TrackFacts {
        TrackFacts(
            id: id, isrc: f.isrc, fingerprint: f.fingerprint, bpm: f.bpm,
            bpmConfidence: f.bpmConfidence, tempoOctaveFlag: f.tempoOctaveFlag,
            beatOffsetMs: f.beatOffsetMs, energy: f.energy, beatStrength: f.beatStrength,
            driveScore: f.driveScore, durationMs: f.durationMs,
            analysisVersion: f.analysisVersion, confirmationCount: f.confirmationCount)
    }
}
