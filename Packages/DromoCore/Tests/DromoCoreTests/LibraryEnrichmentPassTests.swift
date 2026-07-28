import XCTest
@testable import DromoCore

// MARK: - Doubles

/// A source that records when it was asked, so ORDER can be asserted rather than
/// assumed — the whole point of the hardened chain.
private final class SpySource: BPMSourcing, @unchecked Sendable {
    let source: BPMSource
    private let result: Double?
    private let error: Error?
    private let lock = NSLock()
    private var _calls = 0
    /// Shared across sources so relative order is observable.
    private let tape: Tape

    final class Tape: @unchecked Sendable {
        private let lock = NSLock()
        private var order: [BPMSource] = []
        func note(_ s: BPMSource) { lock.lock(); order.append(s); lock.unlock() }
        var asked: [BPMSource] { lock.lock(); defer { lock.unlock() }; return order }
    }

    init(_ source: BPMSource, returns: Double? = nil, throws error: Error? = nil, tape: Tape) {
        self.source = source
        self.result = returns
        self.error = error
        self.tape = tape
    }

    var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }

    func bpm(for item: EnrichmentItem) async throws -> Double? {
        lock.lock(); _calls += 1; lock.unlock()
        tape.note(source)
        if let error { throw error }
        return result
    }
}

private actor RecordingSink: BPMSink {
    private(set) var findings: [String: BPMFinding] = [:]
    func store(bpm: Double, trackID: String) async {
        findings[trackID] = BPMFinding(bpm: bpm, source: .getSongBPM)
    }
    func store(_ finding: BPMFinding, trackID: String) async { findings[trackID] = finding }
    func finding(_ id: String) -> BPMFinding? { findings[id] }
}

private struct Boom: Error {}

private func item(_ id: String, isrc: String? = nil, providerBPM: Double? = nil) -> EnrichmentItem {
    EnrichmentItem(trackID: id, title: "Song \(id)", artist: "Artist",
                   isrc: isrc, providerBPM: providerBPM)
}

// MARK: - Tests

final class LibraryEnrichmentPassTests: XCTestCase {

    private func pass(_ chain: BPMSourceChain, sink: BPMSink,
                      ledger: EnrichmentLedger = InMemoryEnrichmentLedger(),
                      policy: EnrichmentPolicy = fastPolicy(),
                      now: @escaping @Sendable () -> Date = { Date() },
                      gate: @escaping @Sendable () async -> Bool = { true })
        -> LibraryEnrichmentPass {
        LibraryEnrichmentPass(chain: chain, sink: sink, ledger: ledger, policy: policy,
                              now: now, gate: gate, sleep: { _ in })
    }

    private static func fastPolicy() -> EnrichmentPolicy {
        var p = EnrichmentPolicy()
        p.minIntervalNanos = 0          // no real waiting in tests
        return p
    }

    // MARK: Chain order

    func testChainAsksCheapestMostTrustedSourceFirst() async {
        let tape = SpySource.Tape()
        // Deliberately wired in the WRONG order — the chain must fix it, because a
        // mis-wired call site is exactly how Spotify would end up ahead of the table.
        let chain = BPMSourceChain([
            SpySource(.spotify, returns: 150, tape: tape),
            SpySource(.getSongBPM, returns: 140, tape: tape),
            SpySource(.provider, returns: 130, tape: tape),
            SpySource(.trackTable, returns: 120, tape: tape),
        ])
        XCTAssertEqual(chain.order, [.trackTable, .provider, .getSongBPM, .spotify])

        let outcome = await chain.find(for: item("a"))
        XCTAssertEqual(outcome.finding?.source, .trackTable)
        XCTAssertEqual(outcome.finding?.bpm, 120)
        XCTAssertEqual(tape.asked, [.trackTable], "short-circuits on the first hit")
    }

    func testChainFallsThroughMissesToTheNextSource() async {
        let tape = SpySource.Tape()
        let spotify = SpySource(.spotify, returns: 150, tape: tape)
        let chain = BPMSourceChain([
            SpySource(.trackTable, returns: nil, tape: tape),
            SpySource(.getSongBPM, returns: nil, tape: tape),
            spotify,
        ])
        let outcome = await chain.find(for: item("a"))
        XCTAssertEqual(outcome.finding?.source, .spotify, "last resort still answers")
        XCTAssertEqual(tape.asked, [.trackTable, .getSongBPM, .spotify])
    }

    func testFailingSourceDegradesTheChainInsteadOfEndingIt() async {
        let tape = SpySource.Tape()
        let chain = BPMSourceChain([
            SpySource(.trackTable, throws: Boom(), tape: tape),
            SpySource(.getSongBPM, returns: 165, tape: tape),
        ])
        let outcome = await chain.find(for: item("a"))
        XCTAssertEqual(outcome.finding?.bpm, 165)
        XCTAssertEqual(outcome.failedSources, [.trackTable])
        XCTAssertFalse(outcome.isTransientFailure, "a hit means the pass succeeded")
    }

    func testImplausibleTempoIsRejectedAndChainContinues() async {
        let tape = SpySource.Tape()
        let chain = BPMSourceChain([
            SpySource(.trackTable, returns: 12, tape: tape),   // metadata artefact
            SpySource(.getSongBPM, returns: 168, tape: tape),
        ])
        let outcome = await chain.find(for: item("a"))
        XCTAssertEqual(outcome.finding?.bpm, 168)
    }

    // MARK: Caching + attribution

    func testHitsAreCachedWithTheirSourceAndConfidence() async {
        let tape = SpySource.Tape()
        let sink = RecordingSink()
        let chain = BPMSourceChain([SpySource(.getSongBPM, returns: 168, tape: tape)])
        _ = await pass(chain, sink: sink).run([item("a")])

        let finding = await sink.finding("a")
        XCTAssertEqual(finding?.bpm, 168)
        XCTAssertEqual(finding?.source, .getSongBPM)
        XCTAssertEqual(finding?.confidence, BPMSource.getSongBPM.confidence)
    }

    func testProviderTagCostsNoNetworkLookup() async {
        let tape = SpySource.Tape()
        let network = SpySource(.getSongBPM, returns: 140, tape: tape)
        let sink = RecordingSink()
        _ = await pass(BPMSourceChain([network]), sink: sink).run([item("a", providerBPM: 172)])

        let finding = await sink.finding("a")
        XCTAssertEqual(finding?.source, .provider, "the platform's own tag wins for free")
        XCTAssertEqual(finding?.bpm, 172)
        XCTAssertEqual(network.calls, 0, "no HTTP call for a track we already knew")
    }

    func testStrongerSourceSupersedesWeakerOne() {
        let table = BPMFinding(bpm: 170, source: .trackTable)
        let spotify = BPMFinding(bpm: 168, source: .spotify)
        XCTAssertTrue(table.supersedes(spotify))
        XCTAssertFalse(spotify.supersedes(table))
        XCTAssertFalse(spotify.supersedes(spotify), "equal trust ⇒ no churn")
        XCTAssertTrue(spotify.supersedes(nil))
    }

    // MARK: Resumability

    func testResolvedTracksAreNeverLookedUpAgain() async {
        let tape = SpySource.Tape()
        let source = SpySource(.getSongBPM, returns: 168, tape: tape)
        let ledger = InMemoryEnrichmentLedger()
        let sink = RecordingSink()
        let items = [item("a"), item("b")]

        let first = await pass(BPMSourceChain([source]), sink: sink, ledger: ledger).run(items)
        XCTAssertEqual(first.enriched, 2)

        // Second pass over the same library — the whole point of persisting attempts.
        let second = await pass(BPMSourceChain([source]), sink: sink, ledger: ledger).run(items)
        XCTAssertEqual(second.enriched, 0)
        XCTAssertEqual(second.skipped, 2)
        XCTAssertEqual(source.calls, 2, "no repeat lookups across passes")
    }

    func testMissesBackOffBeforeBeingRetried() async {
        let tape = SpySource.Tape()
        let source = SpySource(.getSongBPM, returns: nil, tape: tape)
        let ledger = InMemoryEnrichmentLedger()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))

        let policy = Self.fastPolicy()
        func makePass() -> LibraryEnrichmentPass {
            pass(BPMSourceChain([source]), sink: RecordingSink(), ledger: ledger,
                 policy: policy, now: { clock.current })
        }

        let first = await makePass().run([item("a")])
        XCTAssertEqual(first.missed, 1)

        // Immediately after: still backing off.
        let immediate = await makePass().run([item("a")])
        XCTAssertEqual(immediate.skipped, 1)
        XCTAssertEqual(source.calls, 1)

        // After the backoff window: tried again.
        clock.advance(by: policy.baseBackoff + 60)
        let later = await makePass().run([item("a")])
        XCTAssertEqual(later.missed, 1)
        XCTAssertEqual(source.calls, 2)
    }

    func testTracksStopConsumingBudgetAfterMaxAttempts() async {
        let tape = SpySource.Tape()
        let source = SpySource(.getSongBPM, returns: nil, tape: tape)
        let ledger = InMemoryEnrichmentLedger()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        var policy = Self.fastPolicy()
        policy.maxAttempts = 2

        for _ in 0..<6 {
            _ = await pass(BPMSourceChain([source]), sink: RecordingSink(), ledger: ledger,
                           policy: policy, now: { clock.current }).run([item("a")])
            clock.advance(by: policy.maxBackoff * 2)   // always past any backoff
        }
        XCTAssertEqual(source.calls, policy.maxAttempts,
                       "a permanently-unknown track must stop burning API budget")
    }

    func testTransientFailureDoesNotBurnAnAttempt() async {
        // A flaky hour must not exhaust a track's retry budget — otherwise an outage
        // permanently strands tracks that would have resolved fine.
        let tape = SpySource.Tape()
        let flaky = SpySource(.getSongBPM, throws: Boom(), tape: tape)
        let ledger = InMemoryEnrichmentLedger()

        let result = await pass(BPMSourceChain([flaky]), sink: RecordingSink(),
                                ledger: ledger).run([item("a")])
        XCTAssertEqual(result.deferred, 1)
        XCTAssertEqual(result.missed, 0)
        let attempt = await ledger.attempt(for: "a")
        XCTAssertNil(attempt, "nothing recorded ⇒ full budget intact")
    }

    // MARK: Budget + gate

    func testPerPassLimitDefersTheRest() async {
        let tape = SpySource.Tape()
        let source = SpySource(.getSongBPM, returns: 168, tape: tape)
        var policy = Self.fastPolicy()
        policy.perPassLimit = 3
        let items = (1...10).map { item("t\($0)") }

        let result = await pass(BPMSourceChain([source]), sink: RecordingSink(),
                                policy: policy).run(items)
        XCTAssertEqual(result.enriched, 3)
        XCTAssertEqual(result.deferred, 7, "budget caps the pass; next pass continues")
        XCTAssertEqual(source.calls, 3)
    }

    func testClosedGateStopsThePassWithoutSpendingLookups() async {
        let tape = SpySource.Tape()
        let source = SpySource(.getSongBPM, returns: 168, tape: tape)
        let result = await pass(BPMSourceChain([source]), sink: RecordingSink(),
                                gate: { false }).run([item("a"), item("b")])
        XCTAssertEqual(source.calls, 0, "cellular/opt-out means no lookups at all")
        XCTAssertEqual(result.deferred, 2)
    }

    func testGateDoesNotBlockTheFreeProviderTag() async {
        let sink = RecordingSink()
        let result = await pass(BPMSourceChain([]), sink: sink,
                                gate: { false }).run([item("a", providerBPM: 165)])
        XCTAssertEqual(result.enriched, 1, "an offline, free tag needs no network gate")
        let finding = await sink.finding("a")
        XCTAssertEqual(finding?.source, .provider)
    }

    func testResultAttributesWhichSourceEarnedItsKeep() async {
        let tape = SpySource.Tape()
        let chain = BPMSourceChain([SpySource(.getSongBPM, returns: 168, tape: tape)])
        let result = await pass(chain, sink: RecordingSink())
            .run([item("a"), item("b", providerBPM: 170)])

        XCTAssertEqual(result.bySource[.getSongBPM], 1)
        XCTAssertEqual(result.bySource[.provider], 1)
        XCTAssertEqual(result.attempted, 2)
    }
}
