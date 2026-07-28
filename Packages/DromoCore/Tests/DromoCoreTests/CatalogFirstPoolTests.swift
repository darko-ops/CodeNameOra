import XCTest
@testable import DromoCore

/// Phase 1 exit gate: any library state yields a paceable session, the runner's own
/// music wins when nothing objective separates it from the catalog, and coverage
/// reports the truth about how much of their library Dromo can actually pace to.
final class CatalogFirstPoolTests: XCTestCase {

    private func facts(_ id: String, bpm: Double, energy: Double = 0.6,
                       confidence: Double = 0.9) -> TrackFacts {
        TrackFacts(id: id, bpm: bpm, bpmConfidence: confidence, tempoOctaveFlag: .none,
                   energy: energy, beatStrength: 0.7, durationMs: 200_000,
                   analysisVersion: "test")
    }

    // MARK: - (a) Empty library still spans every cadence

    func testEmptyLibraryGetsFullBPMSpanningCatalogPool() {
        let pool = SessionPoolResolver.initialPool(entries: [], targetCadence: 165)

        XCTAssertFalse(pool.isEmpty, "a runner with nothing connected still gets a pool")
        XCTAssertEqual(pool.libraryTracks.count, 0)
        XCTAssertEqual(pool.catalogTracks.count, FallbackCatalog.tracks.count,
                       "catalog-first: the whole catalog joins, not just the target band")
        // Not merely non-empty — paceable across the range a session can ask for.
        XCTAssertTrue(pool.spans(120...185),
                      "every cadence in normal running range has a candidate within 6 BPM")
    }

    func testEmptyLibrarySessionIsPaceableAtEveryCadence() {
        let pool = SessionPoolResolver.initialPool(entries: [], targetCadence: 170)
        var engine = SelectionEngine()
        // Walk the range: each target must produce a pick whose tempo is genuinely near it.
        for target in stride(from: 130.0, through: 180.0, by: 5) {
            let decision = engine.selectNext(targetCadence: target, currentCadence: target,
                                             candidates: pool.facts, origins: pool.origins)
            guard let decision else { return XCTFail("no candidate at cadence \(target)") }
            XCTAssertLessThanOrEqual(abs(decision.effectiveBPM - target), 8,
                                     "catalog track for \(target) spm is off-tempo")
        }
    }

    func testUnknownBPMLibraryStillReachesCatalog() {
        // The real day-one case: a streaming library, nothing analyzable, no BPM at all.
        let entries = (1...20).map { LibraryEntry(localID: "song\($0)", providerBPM: 0) }
        let pool = SessionPoolResolver.initialPool(entries: entries, targetCadence: 168)

        XCTAssertEqual(pool.libraryTracks.count, 20, "their tracks stay — they're playable")
        XCTAssertTrue(pool.spans(120...185), "…and the catalog supplies the tempo range")
        XCTAssertEqual(LibraryCoverage.measure(pool: pool).tagged, 0)
    }

    // MARK: - (b) The runner's own music wins at equal fit

    func testLibraryTrackDisplacesCatalogTrackAtEqualFit() {
        // Identical facts, different origin: only provenance can break this tie.
        let mine = facts("mine", bpm: 170)
        let theirs = facts("catalog:170", bpm: 170)
        let pool = SessionPool(facts: [theirs, mine],
                               origins: ["mine": .library, "catalog:170": .catalog])

        var engine = SelectionEngine()
        let decision = engine.selectNext(targetCadence: 170, currentCadence: 170,
                                         candidates: pool.facts, origins: pool.origins)
        XCTAssertEqual(decision?.trackID, "mine", "equal fit ⇒ the runner's own track wins")
    }

    func testCatalogStillWinsOnMerit() {
        // Provenance is a tiebreak, not a veto: a clearly better-fitting catalog track
        // must still beat a badly-fitting library track, or the guarantee is hollow.
        let mine = facts("mine", bpm: 120)
        let theirs = facts("catalog:170", bpm: 170)
        let pool = SessionPool(facts: [mine, theirs],
                               origins: ["mine": .library, "catalog:170": .catalog])

        var engine = SelectionEngine()
        let decision = engine.selectNext(targetCadence: 170, currentCadence: 170,
                                         candidates: pool.facts, origins: pool.origins)
        XCTAssertEqual(decision?.trackID, "catalog:170", "merit beats provenance")
    }

    func testOwnershipTiebreakIsSmallerThanRealFitDifference() {
        // Guardrail on the knob: the penalty must not exceed what a meaningful tempo
        // difference is worth, or it would quietly become a veto.
        let config = SelectionConfig()
        let fitPerBPM = config.holdWeights.tempo / config.bpmTolerance
        XCTAssertLessThan(config.catalogPenalty, fitPerBPM * 2,
                          "catalogPenalty outweighs a 2-BPM fit difference — too strong")
    }

    func testUnlistedOriginsCountAsTheRunners() {
        // A pool built without provenance must never be penalised as catalog.
        let a = facts("a", bpm: 170), b = facts("catalog:170", bpm: 170)
        var engine = SelectionEngine()
        let decision = engine.selectNext(targetCadence: 170, currentCadence: 170,
                                         candidates: [b, a], origins: [:])
        XCTAssertEqual(decision?.trackID, "a", "no origins ⇒ plain id tiebreak, no penalty")
    }

    // MARK: - Merge policy

    func testUnionAdmitsWholeCatalogWithoutDuplicatingUserTracks() {
        let mine = [facts("catalog:170", bpm: 170)]   // id collides with a catalog entry
        let pool = CatalogBackfill.merge(userPool: mine, targetCadence: 170)

        XCTAssertEqual(pool.facts.filter { $0.id == "catalog:170" }.count, 1, "no duplicate ids")
        XCTAssertEqual(pool.origin(of: "catalog:170"), .library, "the user's copy keeps its origin")
        XCTAssertEqual(pool.count, FallbackCatalog.tracks.count)
    }

    func testBackfillWhenThinPolicyLeavesRichLibrariesAlone() {
        let rich = (0..<6).map { facts("mine\($0)", bpm: 168 + Double($0)) }
        let pool = CatalogBackfill.merge(userPool: rich, targetCadence: 170,
                                         policy: .backfillWhenThin())
        XCTAssertEqual(pool.catalogTracks.count, 0, "well-covered library needs no catalog")
        XCTAssertEqual(pool.count, rich.count)
    }

    func testResolvedPoolCarriesOrigins() async {
        let cache = InMemoryTrackFactsCache()
        let coord = LibrarySyncCoordinator(api: FakeTrackTable(), cache: cache) { _ in nil }
        let resolver = SessionPoolResolver(coordinator: coord, cache: cache)
        let pool = await resolver.resolvedPool(
            entries: [LibraryEntry(localID: "song1", providerBPM: 168)], targetCadence: 170)

        XCTAssertEqual(pool.origin(of: "song1"), .library)
        XCTAssertTrue(pool.catalogTracks.allSatisfy { $0.id.hasPrefix("catalog:") })
        XCTAssertGreaterThan(pool.catalogTracks.count, 0)
    }

    // MARK: - (c) Coverage math

    func testCoverageCountsOnlyTheRunnersOwnTaggedTracks() {
        let entries = [LibraryEntry(localID: "a", providerBPM: 170),
                       LibraryEntry(localID: "b", providerBPM: 0),
                       LibraryEntry(localID: "c", providerBPM: 150),
                       LibraryEntry(localID: "d", providerBPM: nil)]
        let coverage = LibraryCoverage.measure(entries: entries)

        XCTAssertEqual(coverage.total, 4)
        XCTAssertEqual(coverage.tagged, 2)
        XCTAssertEqual(coverage.untagged, 2)
        XCTAssertEqual(coverage.percent, 50)
    }

    func testCoverageIgnoresCatalogTracksInThePool() {
        let mine = [facts("mine", bpm: 170)]
        let pool = CatalogBackfill.merge(userPool: mine, targetCadence: 170)
        let coverage = LibraryCoverage.measure(pool: pool)

        XCTAssertEqual(coverage.total, 1, "21 catalog tracks must not flatter coverage")
        XCTAssertEqual(coverage.percent, 100)
    }

    func testCoverageDiscountsLowConfidenceTempo() {
        let guessed = [facts("guess", bpm: 170, confidence: 0.2)]
        XCTAssertEqual(LibraryCoverage.measure(facts: guessed).tagged, 0,
                       "an untrustworthy BPM is not a paced track")
    }

    func testEmptyLibraryCoverageIsZeroNotFull() {
        let coverage = LibraryCoverage.measure(entries: [])
        XCTAssertEqual(coverage.fraction, 0)
        XCTAssertTrue(coverage.isEmpty)
        XCTAssertFalse(coverage.carriesSession())
    }

    func testCarriesSessionNeedsBothDepthAndShare() {
        XCTAssertFalse(LibraryCoverage(total: 400, tagged: 11).carriesSession(),
                       "11 tagged tracks can't carry a run regardless of share")
        XCTAssertFalse(LibraryCoverage(total: 400, tagged: 40).carriesSession(),
                       "10% of a big library is still mostly gaps")
        XCTAssertTrue(LibraryCoverage(total: 40, tagged: 20).carriesSession())
    }

    func testCoverageClampsNonsenseInput() {
        let coverage = LibraryCoverage(total: 3, tagged: 99)
        XCTAssertEqual(coverage.tagged, 3)
        XCTAssertEqual(coverage.fraction, 1)
    }
}
