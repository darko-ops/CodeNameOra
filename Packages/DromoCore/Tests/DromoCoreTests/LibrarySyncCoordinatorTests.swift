import XCTest
@testable import DromoCore

final class LibrarySyncCoordinatorTests: XCTestCase {

    private func makeItem(_ id: String, isrc: String? = nil, fp: String? = nil) -> SyncItem {
        SyncItem(localID: id, key: IdentityKey(isrc: isrc, fingerprint: fp))
    }

    func testMissAnalyzesAndPopulates() async {
        let api = FakeTrackTable()
        let cache = InMemoryTrackFactsCache()
        let coord = LibrarySyncCoordinator(api: api, cache: cache) { item in
            stubAnalysis(isrc: item.key.isrc, bpm: 165)
        }
        let facts = await coord.resolve(makeItem("t1", isrc: "USRC11111111"))
        XCTAssertEqual(facts?.bpm, 165)
        XCTAssertEqual(api.populateCalls, 1)
        let cached = await cache.get(IdentityKey(isrc: "USRC11111111"))
        XCTAssertNotNil(cached)
    }

    func testServerHitSkipsAnalysis() async {
        let api = FakeTrackTable()
        api.seed(TrackFacts(id: "x", isrc: "USRC22222222", bpm: 128,
                            bpmConfidence: 0.8, tempoOctaveFlag: .none, analysisVersion: "vdsp-1"))
        let cache = InMemoryTrackFactsCache()
        let analyzeCalls = Counter()
        let coord = LibrarySyncCoordinator(api: api, cache: cache) { _ in
            analyzeCalls.inc(); return stubAnalysis()
        }
        let facts = await coord.resolve(makeItem("t", isrc: "USRC22222222"))
        XCTAssertEqual(facts?.bpm, 128)
        XCTAssertEqual(analyzeCalls.value, 0, "server hit must not analyze")
        XCTAssertEqual(api.populateCalls, 0)
    }

    func testResolveLibraryHitsAndMisses() async {
        let api = FakeTrackTable()
        api.seed(TrackFacts(id: "s", isrc: "HIT00000000A", bpm: 120,
                            bpmConfidence: 0.9, tempoOctaveFlag: .none, analysisVersion: "vdsp-1"))
        let cache = InMemoryTrackFactsCache()
        let coord = LibrarySyncCoordinator(api: api, cache: cache) { item in
            stubAnalysis(isrc: item.key.isrc)
        }
        let items = [
            makeItem("a", isrc: "HIT00000000A"),  // server hit
            makeItem("b", isrc: "MISS0000000B"),  // miss → analyze
            makeItem("c", isrc: "MISS0000000C"),  // miss → analyze
        ]
        let stats = await coord.resolveLibrary(items)
        XCTAssertEqual(stats, .init(cached: 0, lookedUp: 1, analyzed: 2, failed: 0))
        XCTAssertEqual(api.batchCalls, 1, "one batch lookup for the whole library")
        XCTAssertEqual(api.populateCalls, 2)
    }

    func testSecondRunIsFullyCachedNoNetwork() async {
        let api = FakeTrackTable()
        let cache = InMemoryTrackFactsCache()
        let coord = LibrarySyncCoordinator(api: api, cache: cache) { item in
            stubAnalysis(isrc: item.key.isrc)
        }
        let items = [makeItem("a", isrc: "AAAAAAAAAAAA"), makeItem("b", isrc: "BBBBBBBBBBBB")]

        _ = await coord.resolveLibrary(items)
        let batchAfterFirst = api.batchCalls
        let lookupAfterFirst = api.lookupCalls

        let stats2 = await coord.resolveLibrary(items)
        XCTAssertEqual(stats2.cached, 2)
        XCTAssertEqual(api.batchCalls, batchAfterFirst, "second run makes no batch call")
        XCTAssertEqual(api.lookupCalls, lookupAfterFirst, "second run hits zero network")
    }

    func testTwoDevicesSameRecordingSecondGetsHit() async {
        let server = FakeTrackTable()   // shared table

        // Device A: fresh cache, analyzes & populates.
        let aAnalyzed = Counter()
        let deviceA = LibrarySyncCoordinator(api: server, cache: InMemoryTrackFactsCache()) { item in
            aAnalyzed.inc(); return stubAnalysis(isrc: item.key.isrc, bpm: 174)
        }
        _ = await deviceA.resolve(makeItem("x", isrc: "USRC99999999"))
        XCTAssertEqual(aAnalyzed.value, 1)

        // Device B: different cache, same recording → server HIT, no analysis.
        let bAnalyzed = Counter()
        let deviceB = LibrarySyncCoordinator(api: server, cache: InMemoryTrackFactsCache()) { _ in
            bAnalyzed.inc(); return stubAnalysis()
        }
        let facts = await deviceB.resolve(makeItem("x", isrc: "USRC99999999"))
        XCTAssertEqual(facts?.bpm, 174, "B inherited A's measured facts")
        XCTAssertEqual(bAnalyzed.value, 0, "B never analyzed — analyze-once-globally")
        XCTAssertEqual(server.populateCalls, 1, "only A populated")
    }

    func testOnlyIdentityAndNumbersAreUploaded() async throws {
        let api = FakeTrackTable()
        let coord = LibrarySyncCoordinator(api: api, cache: InMemoryTrackFactsCache()) { item in
            stubAnalysis(isrc: item.key.isrc, fingerprint: item.key.fingerprint)
        }
        _ = await coord.resolve(makeItem("t", isrc: "USRC00000001", fp: "abc123"))
        XCTAssertEqual(api.uploaded.count, 1)
        // The payload is an AnalysisResult — structurally no title/artist. Assert the
        // JSON that would go on the wire contains only identity + numeric keys.
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(api.uploaded[0])) as! [String: Any]
        XCTAssertNil(json["title"]); XCTAssertNil(json["artist"]); XCTAssertNil(json["audio"])
        XCTAssertEqual(json["isrc"] as? String, "USRC00000001")
    }

    func testUnanalyzableMissFailsWithoutPopulating() async {
        let api = FakeTrackTable()
        let coord = LibrarySyncCoordinator(api: api, cache: InMemoryTrackFactsCache()) { _ in
            nil   // DRM/unreadable → analysis returns nil
        }
        let stats = await coord.resolveLibrary([makeItem("d", isrc: "DRMDRMDRM001")])
        XCTAssertEqual(stats.failed, 1)
        XCTAssertEqual(api.populateCalls, 0)
    }

    func testLazyRefreshOnNewerAnalysisVersion() async {
        let api = FakeTrackTable()
        api.seed(TrackFacts(id: "s", isrc: "VER000000001", bpm: 130,
                            bpmConfidence: 0.95, tempoOctaveFlag: .none, analysisVersion: "vdsp-2"))
        let cache = InMemoryTrackFactsCache()
        await cache.put(TrackFacts(id: "old", isrc: "VER000000001", bpm: 130,
                                   bpmConfidence: 0.5, tempoOctaveFlag: .none, analysisVersion: "vdsp-1"))
        let coord = LibrarySyncCoordinator(api: api, cache: cache) { _ in nil }

        let refreshed = await coord.refreshIfStale(makeItem("t", isrc: "VER000000001"))
        XCTAssertEqual(refreshed?.analysisVersion, "vdsp-2")
    }
}
