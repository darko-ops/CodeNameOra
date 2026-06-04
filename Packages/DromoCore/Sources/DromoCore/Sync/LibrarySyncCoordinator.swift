import Foundation

/// Lookup-first, analyze-on-miss sync (ARCHITECTURE §6, Phase 3): resolve a library
/// to stored facts cheaply (cache → server lookup), and only locally analyze the
/// long-tail misses — analyze-once-globally pays off here.
///
/// Pure-logic actor: the network (`TrackTableAPI`), local store (`TrackFactsCache`),
/// and on-device analysis (the injected `analyze` closure) are all abstracted, so
/// the whole flow — including two-device fleet behavior — is unit-testable without
/// a server, files, or a device.
public actor LibrarySyncCoordinator {

    public struct Stats: Sendable, Equatable {
        public var cached = 0      // served from local cache, zero network
        public var lookedUp = 0    // server HIT (no analysis)
        public var analyzed = 0    // MISS → analyzed locally + populated to the table
        public var failed = 0      // MISS → unanalyzable (DRM/short) — Phase 6 catalog covers these
    }

    private let api: TrackTableAPI
    private let cache: TrackFactsCache
    private let analyze: @Sendable (SyncItem) async -> AnalysisResult?

    public init(
        api: TrackTableAPI,
        cache: TrackFactsCache,
        analyze: @escaping @Sendable (SyncItem) async -> AnalysisResult?
    ) {
        self.api = api
        self.cache = cache
        self.analyze = analyze
    }

    /// Resolve one track: local cache → server lookup → analyze + populate.
    public func resolve(_ item: SyncItem) async -> TrackFacts? {
        if let hit = await cache.get(item.key) { return hit }
        if let facts = try? await api.lookup(item.key) {
            await cache.put(facts)
            return facts
        }
        return await analyzeAndPopulate(item)
    }

    /// Resolve a whole library on import: cache-first, then ONE batch lookup for the
    /// rest, then analyze the misses. Hits resolve with zero analysis; the caller
    /// runs this in a background Task so the user is never blocked from starting.
    public func resolveLibrary(_ items: [SyncItem]) async -> Stats {
        var stats = Stats()

        var needLookup: [SyncItem] = []
        for item in items {
            if await cache.get(item.key) != nil { stats.cached += 1 }
            else { needLookup.append(item) }
        }
        guard !needLookup.isEmpty else { return stats }

        let results = (try? await api.batchLookup(needLookup.map(\.key))) ?? []
        var misses: [SyncItem] = []
        for item in needLookup {
            if let facts = results.first(where: { $0.key == item.key })?.facts {
                await cache.put(facts)
                stats.lookedUp += 1
            } else {
                misses.append(item)
            }
        }

        // Analyze misses progressively (never blocks hits, which are already resolved).
        for item in misses {
            if await analyzeAndPopulate(item) != nil { stats.analyzed += 1 }
            else { stats.failed += 1 }
        }
        return stats
    }

    /// Lazy `analysis_version` refresh: re-check the server and overwrite the cache
    /// if it now holds a newer analysis for this recording (§7 bookkeeping).
    @discardableResult
    public func refreshIfStale(_ item: SyncItem) async -> TrackFacts? {
        // `try?` flattens the throwing + optional result: a miss or error → nil → keep cache.
        guard let server = try? await api.lookup(item.key) else {
            return await cache.get(item.key)
        }
        let cached = await cache.get(item.key)
        if cached == nil || server.analysisVersion != cached!.analysisVersion {
            await cache.put(server)
        }
        return await cache.get(item.key)
    }

    // MARK: - Private

    private func analyzeAndPopulate(_ item: SyncItem) async -> TrackFacts? {
        guard var result = await analyze(item) else { return nil }
        // Make sure the identity keys we resolved by flow into the upload.
        if result.isrc == nil { result.isrc = item.key.isrc }
        if result.fingerprint == nil { result.fingerprint = item.key.fingerprint }
        guard let facts = try? await api.populate(result) else { return nil }
        await cache.put(facts)
        return facts
    }
}
