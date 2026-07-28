import Foundation

/// How much of the runner's OWN library Dromo can pace to — the number that turns
/// the catalog from a crutch into a bridge. It starts near zero for a streaming
/// library (DRM blocks analysis; see findings/ios-analyzability.md) and climbs as
/// enrichment resolves BPM facts, session by session.
///
/// Deliberately measures the library only: catalog tracks are not the runner's and
/// would flatter the number into meaninglessness.
public struct LibraryCoverage: Sendable, Equatable {

    /// Tracks in the runner's library.
    public let total: Int
    /// Of those, how many have a usable tempo.
    public let tagged: Int

    public init(total: Int, tagged: Int) {
        self.total = max(0, total)
        self.tagged = max(0, min(tagged, max(0, total)))
    }

    /// 0…1. An empty library is 0 — no coverage rather than a vacuous 100%.
    public var fraction: Double { total > 0 ? Double(tagged) / Double(total) : 0 }
    /// Rounded percent for display.
    public var percent: Int { Int((fraction * 100).rounded()) }
    public var untagged: Int { total - tagged }
    public var isEmpty: Bool { total == 0 }

    /// True once the library can carry a session on its own — the point at which the
    /// catalog becomes a backstop rather than the main act.
    public func carriesSession(minTagged: Int = 12, minFraction: Double = 0.25) -> Bool {
        tagged >= minTagged && fraction >= minFraction
    }

    /// Plain-language state for the UI. No percentages in the copy — a runner with 8
    /// tagged tracks cares that it works, not that it's 3%.
    public var summary: String {
        switch (total, tagged) {
        case (0, _):  return "Running on Dromo's mixes — connect your library anytime."
        case (_, 0):  return "Running on Dromo's mixes while we tag your library."
        default:
            return carriesSession()
                ? "\(tagged) of your tracks are tempo-matched."
                : "\(tagged) of your tracks are tempo-matched — Dromo's mixes fill the rest."
        }
    }

    // MARK: - Measurement

    /// Coverage over the library as the pool builder sees it.
    public static func measure(entries: [LibraryEntry]) -> LibraryCoverage {
        LibraryCoverage(total: entries.count,
                        tagged: entries.filter { ($0.providerBPM ?? 0) > 0 }.count)
    }

    /// Coverage over resolved facts. `minConfidence` keeps a guessed tempo from
    /// counting as coverage — an untrustworthy BPM is not a paced track.
    public static func measure(facts: [TrackFacts], minConfidence: Double = 0.5) -> LibraryCoverage {
        LibraryCoverage(total: facts.count,
                        tagged: facts.filter { $0.bpm > 0 && $0.bpmConfidence >= minConfidence }.count)
    }

    /// Coverage of the runner's own music inside a built session pool.
    public static func measure(pool: SessionPool, minConfidence: Double = 0.5) -> LibraryCoverage {
        measure(facts: pool.libraryTracks, minConfidence: minConfidence)
    }
}
