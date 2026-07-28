import Foundation

/// First link in the enrichment chain: ask the Global Track Table whether anyone has
/// already measured this recording (ARCHITECTURE §6 lookup-first). A hit costs one
/// cheap request and gives the best value we can get — an analyzed, corroborated
/// tempo — which is why it runs before any third-party metadata database.
///
/// Deliberately does NOT analyze on a miss: this is the metadata pass, and analysis
/// is Phase 4's contributor path (gated on the accuracy verdict). A miss here just
/// hands the track to the next source.
public struct TrackTableBPMSource: BPMSourcing {

    public let source = BPMSource.trackTable

    private let api: TrackTableAPI
    private let cache: TrackFactsCache
    /// Below this, a stored tempo is a guess, not an answer — pass it down the chain
    /// rather than caching a number the selection engine would discount anyway.
    private let minConfidence: Double
    /// Resolves a local track id to an ISRC when the item didn't carry one.
    ///
    /// Injected and called HERE rather than when items are built, because resolving
    /// identity costs a request of its own: doing it inside the source means it's
    /// spent only on tracks that survived the ledger, the budget, and the gate —
    /// never on the thousands of tracks a pass will not reach today.
    private let resolveIdentity: @Sendable (String) async -> String?

    public init(api: TrackTableAPI, cache: TrackFactsCache, minConfidence: Double = 0.5,
                resolveIdentity: @escaping @Sendable (String) async -> String? = { _ in nil }) {
        self.api = api
        self.cache = cache
        self.minConfidence = minConfidence
        self.resolveIdentity = resolveIdentity
    }

    public func bpm(for item: EnrichmentItem) async throws -> Double? {
        var identity = item.identity
        if identity == nil, let isrc = await resolveIdentity(item.trackID) {
            identity = IdentityKey(isrc: isrc)
        }
        // No recording identity ⇒ nothing to key on. Not a failure: a DRM streaming
        // track without an ISRC is exactly what the text-matching sources are for.
        guard let key = identity, key.isValid else { return nil }

        if let cached = await cache.get(key) { return usable(cached) }

        // A throw here is a TRANSPORT problem and must propagate: the chain records it
        // as transient so the track keeps its retry budget. `nil` is an honest miss.
        guard let facts = try await api.lookup(key) else { return nil }
        await cache.put(facts)
        return usable(facts)
    }

    private func usable(_ facts: TrackFacts) -> Double? {
        facts.bpm > 0 && facts.bpmConfidence >= minConfidence ? facts.bpm : nil
    }
}
