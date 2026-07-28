import XCTest
@testable import DromoCore

/// Phase 4. The contributor path publishes facts keyed by recording, so a wrong one
/// reaches everyone who owns that song — which is why the gate matters more than the
/// pipeline. These pin the gate first, then the flow it protects.
final class ContributionTests: XCTestCase {

    private func result(bpm: Double, confidence: Double, isrc: String = "ISRC0000000A")
        -> AnalysisResult {
        AnalysisResult(isrc: isrc, bpm: bpm, bpmConfidence: confidence,
                       tempoOctaveFlag: .none, analysisVersion: "vdsp-1")
    }

    private func candidate(_ id: String, isrc: String? = "ISRC0000000A",
                           analyzable: Bool = true) -> ContributionCandidate {
        ContributionCandidate(trackID: id,
                              identity: isrc.map { IdentityKey(isrc: $0) },
                              isAnalyzable: analyzable)
    }

    private let ready = DeviceConditions(isCharging: true, isOnUnmeteredNetwork: true,
                                         isLowPowerMode: false, isSessionActive: false)

    // MARK: - The valve

    func testShippedPolicyIsClosedUntilAccuracyIsMeasured() {
        // The project's own rule: nothing is built on on-device analysis until the
        // harness has run on real music. If this fails, someone opened the valve —
        // check that findings/bpm-accuracy.md carries a real verdict.
        XCTAssertEqual(ContributionPolicy.current.verdict, .pending)
        XCTAssertFalse(ContributionPolicy.current.allowsContribution)
        XCTAssertFalse(ContributionPolicy.current.mayPublish(result(bpm: 174, confidence: 0.99)),
                       "not even a maximally-confident reading may be shared while pending")
        XCTAssertNotNil(ContributionPolicy.current.closedReason)
    }

    func testRedVerdictRetiresTheFeatureEntirely() {
        let policy = ContributionPolicy(verdict: .red)
        XCTAssertFalse(policy.allowsContribution)
        XCTAssertFalse(policy.mayPublish(result(bpm: 174, confidence: 1.0)))
    }

    func testYellowPublishesOnlyConfidentReadings() {
        // The stated YELLOW mitigation: trust the confident ones and nothing else.
        let policy = ContributionPolicy(verdict: .yellow)
        XCTAssertTrue(policy.mayPublish(result(bpm: 174, confidence: 0.85)))
        XCTAssertFalse(policy.mayPublish(result(bpm: 174, confidence: 0.6)),
                       "a middling reading is exactly what YELLOW says not to share")
    }

    func testGreenPublishesAboveTheFloorAndNeverAGuess() {
        let policy = ContributionPolicy(verdict: .green)
        XCTAssertTrue(policy.mayPublish(result(bpm: 174, confidence: 0.6)))
        XCTAssertFalse(policy.mayPublish(result(bpm: 174, confidence: 0.2)))
        XCTAssertFalse(policy.mayPublish(result(bpm: 0, confidence: 0.9)), "no tempo, no fact")
    }

    // MARK: - What gets scheduled

    func testNothingIsScheduledWhileTheVerdictIsPending() {
        let plan = ContributionPlanner.plan(candidates: [candidate("a")],
                                            policy: ContributionPolicy(verdict: .pending),
                                            conditions: ready)
        XCTAssertTrue(plan.batch.isEmpty)
        XCTAssertEqual(plan.hold, .verdictPending)
    }

    func testAnalysisYieldsToTheRunItWouldCompeteWith() {
        var conditions = ready
        conditions.isSessionActive = true
        let plan = ContributionPlanner.plan(candidates: [candidate("a")],
                                            policy: ContributionPolicy(verdict: .green),
                                            conditions: conditions)
        XCTAssertEqual(plan.hold, .sessionActive)
    }

    func testAnalysisWaitsForPowerAndWiFi() {
        let policy = ContributionPolicy(verdict: .green)
        var unplugged = ready; unplugged.isCharging = false
        var cellular = ready; cellular.isOnUnmeteredNetwork = false
        var saving = ready; saving.isLowPowerMode = true

        XCTAssertEqual(ContributionPlanner.plan(candidates: [candidate("a")], policy: policy,
                                                conditions: unplugged).hold, .notCharging)
        XCTAssertEqual(ContributionPlanner.plan(candidates: [candidate("a")], policy: policy,
                                                conditions: cellular).hold, .meteredNetwork)
        XCTAssertEqual(ContributionPlanner.plan(candidates: [candidate("a")], policy: policy,
                                                conditions: saving).hold, .lowPowerMode)
    }

    func testDRMAndIdentitylessTracksAreExcludedWithoutTrying() {
        let plan = ContributionPlanner.plan(
            candidates: [candidate("drm", analyzable: false),
                         candidate("anon", isrc: nil),
                         candidate("ok")],
            policy: ContributionPolicy(verdict: .green), conditions: ready)

        XCTAssertEqual(plan.batch.map(\.trackID), ["ok"])
        XCTAssertEqual(plan.unanalyzable, 1, "assetURL == nil is DRM — never circumvented")
        XCTAssertEqual(plan.noIdentity, 1, "a fact with no recording id can't be shared")
    }

    func testRecordingsTheTableAlreadyKnowsAreNotReanalyzed() {
        let known = IdentityKey(isrc: "ISRC0000000A").storageKey
        let plan = ContributionPlanner.plan(
            candidates: [candidate("a"), candidate("b", isrc: "ISRC0000000B")],
            policy: ContributionPolicy(verdict: .green), conditions: ready,
            alreadyKnown: [known])

        XCTAssertEqual(plan.batch.map(\.trackID), ["b"])
        XCTAssertEqual(plan.alreadyKnown, 1, "no battery spent learning what's known")
    }

    func testBatchesAreBoundedAndTheRestDeferred() {
        let candidates = (1...50).map { candidate("t\($0)", isrc: "ISRC000000\($0)") }
        let plan = ContributionPlanner.plan(candidates: candidates,
                                            policy: ContributionPolicy(verdict: .green),
                                            conditions: ready, batchLimit: 10)
        XCTAssertEqual(plan.batch.count, 10)
        XCTAssertEqual(plan.deferred, 40)
    }

    // MARK: - End to end (exit gate)

    /// Local file → analysis → publish → a SECOND device inherits the fact by ISRC,
    /// with no analysis of its own. The point of analyze-once-globally.
    func testAnalyzedFactReachesASecondClientByISRC() async {
        let server = FakeTrackTable()
        let policy = ContributionPolicy(verdict: .green)

        // Device 1: owns the file, analyzes it, publishes what the policy allows.
        let analyzed = result(bpm: 168, confidence: 0.9)
        XCTAssertTrue(policy.mayPublish(analyzed))
        let published = try? await server.populate(analyzed)
        XCTAssertEqual(published?.bpm, 168)

        // Device 2: streams the same recording, can't analyze it, looks it up.
        let inherited = try? await server.lookup(IdentityKey(isrc: "ISRC0000000A"))
        XCTAssertEqual(inherited?.bpm, 168, "the streaming device inherits the fact")
        XCTAssertEqual(server.populateCalls, 1, "it never had to analyze anything")
    }

    func testNothingReachesTheServerWhileTheValveIsClosed() async {
        let server = FakeTrackTable()
        let policy = ContributionPolicy.current          // the shipped one
        let analyzed = result(bpm: 168, confidence: 0.95)

        if policy.mayPublish(analyzed) {
            _ = try? await server.populate(analyzed)
        }
        XCTAssertEqual(server.populateCalls, 0,
                       "a closed valve means the network is never touched")
    }
}
