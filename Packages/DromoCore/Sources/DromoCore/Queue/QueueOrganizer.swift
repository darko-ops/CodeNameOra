import Foundation

/// How the browsing "up next" queue is ordered. Unlike the live-run engine (which
/// reacts to cadence), this organizes a queue for listening/previewing — by the
/// runner's needs, not alphabetically.
public enum QueueOrder: String, CaseIterable, Sendable {
    case inOrder      // as the list was given
    case shuffle      // random (deterministic given a seed)
    case tempoFlow    // smooth BPM steps from the seed — a coherent, run-friendly flow
    case energyArc    // warm-up → build → peak → ease
    case taste        // learned preference first

    public var label: String {
        switch self {
        case .inOrder:   return "In order"
        case .shuffle:   return "Shuffle"
        case .tempoFlow: return "Tempo flow"
        case .energyArc: return "Energy arc"
        case .taste:     return "For you"
        }
    }
}

/// Pure, deterministic queue ordering. The currently-playing / tapped track is the
/// `seed` and is always pinned first; the rest are ordered per `order`. Signals are
/// passed in (taste weights) so this stays free of storage/UI. Degrades gracefully
/// when signals are thin (e.g. unknown BPM, no taste history).
public enum QueueOrganizer {

    public static func organize(_ tracks: [Track], order: QueueOrder, seed: Track?,
                                preferences: [String: Double], shuffleSeed: UInt64 = 0) -> [Track] {
        var rest = tracks
        var head: [Track] = []
        if let seed, let i = rest.firstIndex(where: { $0.id == seed.id }) {
            head = [rest.remove(at: i)]
        }

        let ordered: [Track]
        switch order {
        case .inOrder:
            ordered = rest
        case .shuffle:
            var rng = SplitMix64(seed: shuffleSeed)
            ordered = rest.shuffled(using: &rng)
        case .tempoFlow:
            ordered = tempoFlow(rest, from: head.first, preferences: preferences)
        case .energyArc:
            ordered = energyArc(rest, preferences: preferences)
        case .taste:
            ordered = byTaste(rest, preferences: preferences)
        }
        return head + ordered
    }

    // MARK: - Tempo flow (smooth BPM steps, greedy nearest-neighbour)

    private static func tempoFlow(_ tracks: [Track], from seed: Track?,
                                  preferences: [String: Double]) -> [Track] {
        let known = tracks.filter { $0.bpm > 0 }
        let unknown = tracks.filter { $0.bpm <= 0 }
        guard !known.isEmpty else { return byTaste(tracks, preferences: preferences) }

        var remaining = known
        var result: [Track] = []
        var lastBPM = (seed?.bpm ?? 0) > 0 ? seed!.bpm : median(known.map(\.bpm))

        while let next = remaining.min(by: { a, b in
            let da = abs(a.bpm - lastBPM), db = abs(b.bpm - lastBPM)
            if da != db { return da < db }            // closest tempo wins
            return prefersFirst(a, b, preferences)     // tie-break: taste, then id
        }) {
            result.append(next)
            lastBPM = next.bpm
            remaining.removeAll { $0.id == next.id }
        }
        return interleave(result, unknown)             // spread unknown-BPM tracks through
    }

    // MARK: - Energy arc (rise to a peak, then ease)

    private static func energyArc(_ tracks: [Track], preferences: [String: Double]) -> [Track] {
        let bpms = tracks.map(\.bpm).filter { $0 > 0 }
        let lo = bpms.min() ?? 0, hi = bpms.max() ?? 0
        func intensity(_ t: Track) -> Double {
            let bpmNorm = (hi > lo && t.bpm > 0) ? (t.bpm - lo) / (hi - lo) : 0.5
            return 0.5 * t.energyLevel + 0.5 * bpmNorm
        }
        let sorted = tracks.sorted { a, b in
            let ia = intensity(a), ib = intensity(b)
            if ia != ib { return ia < ib }
            return prefersFirst(a, b, preferences)
        }
        // Bitonic mountain: every other track climbs, the rest descend after the peak.
        var up: [Track] = [], down: [Track] = []
        for (i, t) in sorted.enumerated() {
            if i.isMultiple(of: 2) { up.append(t) } else { down.append(t) }
        }
        return up + down.reversed()
    }

    // MARK: - Taste

    private static func byTaste(_ tracks: [Track], preferences: [String: Double]) -> [Track] {
        tracks.sorted { prefersFirst($0, $1, preferences) }
    }

    // MARK: - Helpers

    /// Order by taste weight desc (unknown = neutral 0.5), then id for determinism.
    private static func prefersFirst(_ a: Track, _ b: Track, _ prefs: [String: Double]) -> Bool {
        let pa = prefs[a.id] ?? 0.5, pb = prefs[b.id] ?? 0.5
        return pa != pb ? pa > pb : a.id < b.id
    }

    private static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.sorted()[xs.count / 2]
    }

    /// Spread `extra` evenly through `main` so unknown-BPM tracks aren't all dumped together.
    private static func interleave(_ main: [Track], _ extra: [Track]) -> [Track] {
        guard !extra.isEmpty else { return main }
        guard !main.isEmpty else { return extra }
        let step = Double(main.count + extra.count) / Double(extra.count)
        var out: [Track] = []
        var ei = 0
        var nextAt = step
        for t in main {
            out.append(t)
            while ei < extra.count, Double(out.count) >= nextAt {
                out.append(extra[ei]); ei += 1; nextAt += step
            }
        }
        while ei < extra.count { out.append(extra[ei]); ei += 1 }
        return out
    }
}

/// Small seeded PRNG so `shuffle` is deterministic given a seed (testable; the app
/// passes a random seed for real shuffles).
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
