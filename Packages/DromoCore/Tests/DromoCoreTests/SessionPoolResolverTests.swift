import XCTest
@testable import DromoCore

final class SessionPoolResolverTests: XCTestCase {

    private func makeResolver(_ api: FakeTrackTable, _ cache: InMemoryTrackFactsCache,
                              analyze: @escaping @Sendable (SyncItem) async -> AnalysisResult? = { _ in nil })
        -> SessionPoolResolver {
        let coord = LibrarySyncCoordinator(api: api, cache: cache, analyze: analyze)
        return SessionPoolResolver(coordinator: coord, cache: cache)
    }

    func testInitialPoolUsesProviderBPMPlusCatalog() {
        let entries = [LibraryEntry(localID: "song1", providerBPM: 168, energy: 0.6, durationMs: 200_000)]
        let pool = SessionPoolResolver.initialPool(entries: entries, targetCadence: 170)
        XCTAssertTrue(pool.contains { $0.id == "song1" && $0.bpm == 168 }, "keeps the user's track")
        XCTAssertGreaterThan(pool.count, 1, "catalog backfills near the target")
    }

    func testInitialPoolKeepsUntaggedPlayableTracks() {
        // A real library track with unknown BPM (0) is still playable — it must stay
        // in the pool (regression: it was being dropped, leaving nothing to play).
        let entries = [LibraryEntry(localID: "song1", providerBPM: 0)]
        let pool = SessionPoolResolver.initialPool(entries: entries, targetCadence: 170, catalog: [])
        XCTAssertTrue(pool.contains { $0.id == "song1" })
    }

    func testResolvedPoolPrefersTrackTableFacts() async {
        let api = FakeTrackTable()
        api.seed(TrackFacts(id: "srv", isrc: "ISRC0000000Z", bpm: 176, bpmConfidence: 0.95,
                            tempoOctaveFlag: .none, analysisVersion: "vdsp-1"))
        let cache = InMemoryTrackFactsCache()
        let resolver = makeResolver(api, cache)
        let entries = [LibraryEntry(localID: "song1", identity: IdentityKey(isrc: "ISRC0000000Z"),
                                    providerBPM: 150, energy: 0.5, durationMs: 200_000)]
        let pool = await resolver.resolvedPool(entries: entries, targetCadence: 176)
        let song = pool.first { $0.id == "song1" }
        XCTAssertEqual(song?.bpm, 176, "Track Table fact overrides the provider's 150")
    }

    func testResolvedPoolAnalyzesMissThenResolves() async {
        let api = FakeTrackTable()
        let cache = InMemoryTrackFactsCache()
        let resolver = makeResolver(api, cache) { item in
            stubAnalysis(isrc: item.key.isrc, bpm: 162)   // miss → analyzed
        }
        let entries = [LibraryEntry(localID: "song1", identity: IdentityKey(isrc: "ISRC0000000M"),
                                    providerBPM: 150)]
        let pool = await resolver.resolvedPool(entries: entries, targetCadence: 162)
        XCTAssertEqual(pool.first { $0.id == "song1" }?.bpm, 162)
        XCTAssertEqual(api.populateCalls, 1, "miss populated the shared table")
    }

    func testResolvedPoolFallsBackToProviderWithoutIdentity() async {
        let resolver = makeResolver(FakeTrackTable(), InMemoryTrackFactsCache())
        let entries = [LibraryEntry(localID: "song1", identity: nil, providerBPM: 168)]
        let pool = await resolver.resolvedPool(entries: entries, targetCadence: 170)
        XCTAssertEqual(pool.first { $0.id == "song1" }?.bpm, 168, "no identity → provider BPM kept")
    }

    func testEmptyLibraryResolvesToCatalogOnly() async {
        let resolver = makeResolver(FakeTrackTable(), InMemoryTrackFactsCache())
        let pool = await resolver.resolvedPool(entries: [], targetCadence: 165)
        XCTAssertFalse(pool.isEmpty, "unanalyzable/empty library still gets a catalog pool")
    }
}
