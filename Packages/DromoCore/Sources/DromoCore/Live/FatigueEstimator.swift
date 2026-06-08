import Foundation

/// Estimates natural fatigue from the live run so the engine can SOFTEN its response
/// when a runner is genuinely tiring — rather than blasting aggressive high-tempo music
/// at someone fading at mile 18, which fights them instead of reading them.
///
/// Produces a coefficient: **1.0 = fresh**, down to `floor` = deeply fatigued. The
/// selection engine multiplies its desired-BPM *push* by this (gentler nudges when
/// tired) and bends track energy toward "sustained" as it drops.
///
/// Three signals, combined and weighted:
///  1. **Trend** — is cadence progressively dropping vs a few minutes ago?
///  2. **Duration** — fatigue naturally builds over a long effort.
///  3. **Gap persistence** — behind pace for a sustained stretch (structural, not a blip).
///
/// Pure + deterministic (time is injected), fed one sample per ~second from the live
/// loop. Works in CADENCE (spm) — the reliable on-device signal — not GPS pace.
public struct FatigueEstimator {

    public struct Config: Sendable, Equatable {
        /// Never fully stop nudging — just make it very gentle.
        public var floor: Double = 0.2

        // Duration: fatigue starts mattering after `onset`, full by `full` minutes.
        public var durationOnsetMinutes: Double = 20
        public var durationFullMinutes: Double = 60

        // Trend: compare the last `window` s of cadence to a `window` ending
        // `baselineAgo` s back. A drop of `fullDrop` spm = a maximal trend signal.
        public var trendWindowSeconds: Double = 60
        public var trendBaselineAgoSeconds: Double = 180
        public var trendFullDropSpm: Double = 12

        // Gap persistence: fraction of the last `window` s spent more than
        // `behindThreshold` spm behind target.
        public var behindThresholdSpm: Double = 4
        public var persistenceWindowSeconds: Double = 120

        // How much each signal pulls the coefficient down (these sum to ≤ 1).
        public var trendWeight: Double = 0.4
        public var durationWeight: Double = 0.3
        public var persistenceWeight: Double = 0.3

        public init() {}
    }

    private struct Sample { let t: TimeInterval; let cadence: Double; let gap: Double }

    public let config: Config
    private var samples: [Sample] = []
    private var startTime: TimeInterval?

    public init(config: Config = .init()) { self.config = config }

    /// Feed one live sample. `cadence` ≤ 0 (standing / no pedometer signal) is ignored
    /// so it doesn't pollute the trend or look like a huge "behind" gap.
    public mutating func ingest(now: TimeInterval, cadence: Double, gap: Double) {
        guard cadence > 0 else { return }
        if startTime == nil { startTime = now }
        samples.append(Sample(t: now, cadence: cadence, gap: gap))

        let keep = max(config.trendBaselineAgoSeconds + config.trendWindowSeconds,
                       config.persistenceWindowSeconds) + 5
        let cutoff = now - keep
        if let first = samples.first, first.t < cutoff {
            samples.removeAll { $0.t < cutoff }
        }
    }

    /// Current fatigue coefficient (1.0 fresh → `floor`). Pass the same monotonic clock.
    public func coefficient(now: TimeInterval) -> Double {
        let elapsedMin = startTime.map { (now - $0) / 60 } ?? 0
        let raw = 1.0
            - trendFactor(now: now) * config.trendWeight
            - durationFactor(elapsedMin) * config.durationWeight
            - persistenceFactor(now: now) * config.persistenceWeight
        return max(config.floor, min(1.0, raw))
    }

    // MARK: - Signals (each 0 = no fatigue → 1 = strong)

    private func trendFactor(now: TimeInterval) -> Double {
        let recent = avgCadence(from: now - config.trendWindowSeconds, to: now)
        let baseTo = now - config.trendBaselineAgoSeconds
        let baseFrom = baseTo - config.trendWindowSeconds
        guard let r = recent, let b = avgCadence(from: baseFrom, to: baseTo), b > 0 else {
            return 0
        }
        let drop = b - r   // positive = slowed since the baseline window
        return max(0, min(1, drop / config.trendFullDropSpm))
    }

    private func durationFactor(_ elapsedMin: Double) -> Double {
        guard elapsedMin > config.durationOnsetMinutes else { return 0 }
        let span = max(1, config.durationFullMinutes - config.durationOnsetMinutes)
        return min(1, (elapsedMin - config.durationOnsetMinutes) / span)
    }

    private func persistenceFactor(now: TimeInterval) -> Double {
        let window = samples.filter { $0.t >= now - config.persistenceWindowSeconds }
        // Need a reasonably full window of history before trusting this signal.
        guard window.count >= 10, let first = window.first,
              now - first.t >= config.persistenceWindowSeconds * 0.75 else { return 0 }
        let behind = window.filter { $0.gap > config.behindThresholdSpm }.count
        return Double(behind) / Double(window.count)
    }

    private func avgCadence(from: TimeInterval, to: TimeInterval) -> Double? {
        let xs = samples.lazy.filter { $0.t >= from && $0.t <= to }.map { $0.cadence }
        let arr = Array(xs)
        guard !arr.isEmpty else { return nil }
        return arr.reduce(0, +) / Double(arr.count)
    }
}
