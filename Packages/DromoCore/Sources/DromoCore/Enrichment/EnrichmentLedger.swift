import Foundation

/// What the enricher remembers about one track between passes. Without this, every
/// app launch re-queries the same permanently-unknown tracks forever: the library's
/// long tail would burn the whole API budget and the tracks that COULD resolve would
/// never be reached.
public struct EnrichmentAttempt: Sendable, Equatable, Codable {
    public let trackID: String
    /// Consecutive passes that found nothing. Drives exponential backoff.
    public var attempts: Int
    public var lastAttemptAt: Date
    /// True once a BPM was found — the track never needs the chain again.
    public var resolved: Bool

    public init(trackID: String, attempts: Int = 0,
                lastAttemptAt: Date = .distantPast, resolved: Bool = false) {
        self.trackID = trackID
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
        self.resolved = resolved
    }
}

/// Persistence for those attempts. The app backs this with GRDB; tests use memory.
public protocol EnrichmentLedger: Sendable {
    func attempt(for trackID: String) async -> EnrichmentAttempt?
    func record(_ attempt: EnrichmentAttempt) async
}

/// In-memory ledger — tests, previews, and the default when the app hasn't wired
/// persistence (behaves like "nothing has ever been tried").
public actor InMemoryEnrichmentLedger: EnrichmentLedger {
    private var attempts: [String: EnrichmentAttempt] = [:]
    public init() {}
    public func attempt(for trackID: String) async -> EnrichmentAttempt? { attempts[trackID] }
    public func record(_ attempt: EnrichmentAttempt) async { attempts[attempt.trackID] = attempt }
}

/// The budget rules for a background pass. Every number here is an API-spend or
/// battery decision, so they live together rather than scattered as literals.
public struct EnrichmentPolicy: Sendable, Equatable {

    /// Stop retrying a track after this many empty passes. The catalog covers what
    /// never resolves (Phase 1), so giving up is a real option, not a failure.
    public var maxAttempts: Int = 4
    /// First retry delay; doubles per attempt.
    public var baseBackoff: TimeInterval = 6 * 3600
    /// Ceiling on that doubling.
    public var maxBackoff: TimeInterval = 14 * 24 * 3600
    /// Most tracks to look up in ONE pass, so a 10,000-track import doesn't try to
    /// resolve itself in a single sitting.
    public var perPassLimit: Int = 250
    /// Spacing between network lookups (~1 req/s free tier).
    public var minIntervalNanos: UInt64 = 1_100_000_000

    public init() {}

    /// When may this track be tried again? `nil` ⇒ never (budget exhausted).
    public func nextEligible(after attempt: EnrichmentAttempt) -> Date? {
        if attempt.resolved { return nil }
        guard attempt.attempts < maxAttempts else { return nil }
        let delay = min(maxBackoff, baseBackoff * pow(2, Double(attempt.attempts - 1)))
        return attempt.lastAttemptAt.addingTimeInterval(attempt.attempts <= 0 ? 0 : delay)
    }

    public func isEligible(_ attempt: EnrichmentAttempt?, now: Date) -> Bool {
        guard let attempt else { return true }              // never tried
        guard let next = nextEligible(after: attempt) else { return false }
        return now >= next
    }
}
