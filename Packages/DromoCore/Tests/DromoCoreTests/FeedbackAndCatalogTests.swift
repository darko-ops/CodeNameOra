import XCTest
@testable import DromoCore

/// A preference store spy that also records whether it was touched.
private final class SpyPreferences: PreferenceStoring, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var records: [(SubjectiveSignal, String)] = []
    private var w: [String: Double] = [:]
    func record(_ signal: SubjectiveSignal, trackID: String) async {
        lock.lock(); defer { lock.unlock() }
        records.append((signal, trackID))
        w[trackID] = (w[trackID] ?? 0.5) + (signal == .liked ? 0.4 : 0)
    }
    func weights() async -> [String: Double] { lock.lock(); defer { lock.unlock() }; return w }
}

final class FeedbackAndCatalogTests: XCTestCase {

    private func facts(_ id: String, bpm: Double, energy: Double = 0.5) -> TrackFacts {
        TrackFacts(id: id, bpm: bpm, bpmConfidence: 0.9, tempoOctaveFlag: .none,
                   energy: energy, beatStrength: 0.6, analysisVersion: "vdsp-1")
    }

    // MARK: Two feedback stores are provably separate

    func testObjectiveGoesToServerOnly() async {
        let api = FakeTrackTable()
        api.seed(TrackFacts(id: "srv-1", isrc: "ISRC00000001", bpm: 170,
                            bpmConfidence: 0.3, tempoOctaveFlag: .none, analysisVersion: "vdsp-1"))
        let prefs = SpyPreferences()
        let router = FeedbackRouter(api: api, preferences: prefs, clientID: "dev-1")

        _ = await router.reportObjective(.confirmedOnTempo, trackID: "srv-1")

        XCTAssertEqual(api.confirmCalls, 1, "objective hits the global table")
        XCTAssertTrue(prefs.records.isEmpty, "objective must NOT touch the per-user store")
    }

    func testSubjectiveGoesToPreferencesOnly() async {
        let api = FakeTrackTable()
        let prefs = SpyPreferences()
        let router = FeedbackRouter(api: api, preferences: prefs, clientID: "dev-1")

        await router.reportSubjective(.liked, trackID: "t1")

        XCTAssertEqual(prefs.records.count, 1, "subjective goes to the private store")
        XCTAssertEqual(api.confirmCalls, 0, "subjective must NEVER hit the global table")
    }

    func testPreferenceWeightsInfluenceSelection() async {
        let prefs = InMemoryPreferenceStore()
        await prefs.record(.liked, trackID: "loved")
        let weights = await prefs.weights()

        var engine = SelectionEngine()
        let pool = [facts("plain", bpm: 170), facts("loved", bpm: 170)]
        let d = engine.selectNext(targetCadence: 170, currentCadence: 170,
                                  candidates: pool, preferences: weights)
        XCTAssertEqual(d?.trackID, "loved")
    }

    // MARK: Fallback catalog — same schema, no special-casing

    func testCatalogTracksAreOrdinaryCandidates() {
        var engine = SelectionEngine()
        let pool = FallbackCatalog.tracks(aroundBPM: 170, tolerance: 8)
        XCTAssertFalse(pool.isEmpty)
        let d = engine.selectNext(targetCadence: 170, currentCadence: 170, candidates: pool)
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.effectiveBPM, 170, accuracy: 8)
    }

    func testEmptyLibraryStillGetsPlayableSessionViaCatalog() {
        let augmented = CatalogBackfill.augment(userPool: [], targetCadence: 165)
        XCTAssertFalse(augmented.isEmpty, "thin/empty library is backfilled from the catalog")
        var engine = SelectionEngine()
        let d = engine.selectNext(targetCadence: 165, currentCadence: 165, candidates: augmented)
        XCTAssertNotNil(d, "engine can run a paced session entirely on catalog tracks")
    }

    func testBackfillLeavesRichLibraryUntouched() {
        let rich = (160...180).map { facts("u\($0)", bpm: Double($0)) }
        let augmented = CatalogBackfill.augment(userPool: rich, targetCadence: 170)
        XCTAssertEqual(augmented.count, rich.count, "enough local coverage → no catalog added")
    }

    func testCatalogSchemaMatchesTrackFacts() throws {
        // Catalog tracks encode identically to any other facts (same schema).
        let t = FallbackCatalog.tracks.first!
        let data = try JSONEncoder().encode(t)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["bpm"])
        XCTAssertEqual(json["analysis_version"] as? String, "catalog")
    }
}
