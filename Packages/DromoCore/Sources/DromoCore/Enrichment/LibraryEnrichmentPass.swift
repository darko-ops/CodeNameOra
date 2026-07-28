import Foundation

/// One background pass over the library's untagged tracks: walk the source chain
/// cheapest-first, cache every hit with its provenance, and remember what was tried
/// so the next pass starts where this one stopped.
///
/// This is the engine behind "your library gains BPM continuously, without the user
/// ever asking". Three properties matter more than throughput:
///
///   **Resumable** — a ledger records every attempt, so a pass killed mid-flight (app
///   backgrounded, run started) resumes rather than restarting, and tracks that will
///   never resolve stop consuming budget after `maxAttempts`.
///
///   **Budgeted** — `perPassLimit` caps lookups per pass and `minIntervalNanos` paces
///   them; a source that errors backs off exponentially instead of hammering.
///
///   **Interruptible** — the gate is checked before every network lookup, so leaving
///   Wi-Fi (or starting a run) stops the pass at the next boundary. A session is never
///   blocked on enrichment; enrichment yields to the session.
public actor LibraryEnrichmentPass {

    public struct Result: Sendable, Equatable {
        /// Tracks whose BPM was found and cached this pass.
        public var enriched = 0
        /// Tried, nothing found — will be retried after backoff.
        public var missed = 0
        /// Skipped: resolved already, backing off, or out of attempts.
        public var skipped = 0
        /// Not reached because the pass hit its budget or the gate closed.
        public var deferred = 0
        /// What answered, so the app can log which source is actually earning its keep.
        public var bySource: [BPMSource: Int] = [:]

        public init() {}

        public var attempted: Int { enriched + missed }
    }

    public struct Progress: Sendable, Equatable {
        public var done: Int
        public var total: Int
        public var enriched: Int

        public init(done: Int, total: Int, enriched: Int) {
            self.done = done
            self.total = total
            self.enriched = enriched
        }
    }

    private let chain: BPMSourceChain
    private let sink: BPMSink
    private let ledger: EnrichmentLedger
    private let policy: EnrichmentPolicy
    private let now: @Sendable () -> Date
    /// "May I use the network right now?" — the app wires this to Wi-Fi/opt-in state.
    /// Checked before EVERY network lookup, so conditions changing mid-pass is handled.
    private let gate: @Sendable () async -> Bool
    private let sleep: @Sendable (UInt64) async -> Void

    public init(
        chain: BPMSourceChain,
        sink: BPMSink,
        ledger: EnrichmentLedger = InMemoryEnrichmentLedger(),
        policy: EnrichmentPolicy = .init(),
        now: @escaping @Sendable () -> Date = { Date() },
        gate: @escaping @Sendable () async -> Bool = { true },
        sleep: (@Sendable (UInt64) async -> Void)? = nil
    ) {
        self.chain = chain
        self.sink = sink
        self.ledger = ledger
        self.policy = policy
        self.now = now
        self.gate = gate
        self.sleep = sleep ?? { nanos in try? await Task.sleep(nanoseconds: nanos) }
    }

    @discardableResult
    public func run(_ items: [EnrichmentItem],
                    onProgress: (@Sendable (Progress) -> Void)? = nil) async -> Result {
        var result = Result()
        var looked = 0            // network lookups spent this pass (the budget)

        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                result.deferred += items.count - index
                break
            }

            let attempt = await ledger.attempt(for: item.trackID)
            guard policy.isEligible(attempt, now: now()) else {
                result.skipped += 1
                continue
            }

            // The platform's own tag costs nothing — take it without spending budget
            // or waiting on the gate, which is the whole point of ordering it early.
            if let bpm = item.providerBPM, bpm > 0 {
                await store(BPMFinding(bpm: bpm, source: .provider), item, &result)
                onProgress?(Progress(done: index + 1, total: items.count, enriched: result.enriched))
                continue
            }

            guard looked < policy.perPassLimit else {
                result.deferred += 1                      // budget spent — next pass takes it
                continue
            }
            guard await gate() else {
                result.deferred += items.count - index     // conditions closed — stop cleanly
                break
            }

            let outcome = await chain.find(for: item)
            looked += 1

            if let finding = outcome.finding {
                await store(finding, item, &result)
            } else {
                // A transient source failure must not burn an attempt — otherwise a
                // flaky hour would exhaust a track's budget and it'd never be tried
                // again. Only a clean "nobody knows this track" counts against it.
                if !outcome.isTransientFailure {
                    await ledger.record(EnrichmentAttempt(
                        trackID: item.trackID,
                        attempts: (attempt?.attempts ?? 0) + 1,
                        lastAttemptAt: now(), resolved: false))
                    result.missed += 1
                } else {
                    result.deferred += 1
                }
            }

            onProgress?(Progress(done: index + 1, total: items.count, enriched: result.enriched))
            if index < items.count - 1, policy.minIntervalNanos > 0 {
                await sleep(policy.minIntervalNanos)
            }
        }
        return result
    }

    private func store(_ finding: BPMFinding, _ item: EnrichmentItem,
                       _ result: inout Result) async {
        await sink.store(finding, trackID: item.trackID)
        await ledger.record(EnrichmentAttempt(
            trackID: item.trackID, attempts: 0, lastAttemptAt: now(), resolved: true))
        result.enriched += 1
        result.bySource[finding.source, default: 0] += 1
    }
}
