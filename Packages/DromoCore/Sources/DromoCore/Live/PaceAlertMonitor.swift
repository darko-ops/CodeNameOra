import Foundation

/// The pace-deviation alarm — a HARD ±threshold band around the target pace, distinct
/// from the engine's gentle music nudges (`SelectionEngine.Nudge`). When the runner
/// drifts outside the band, the app sounds a beep: one tone for too-slow, another for
/// too-fast. While still out of range, it re-fires every `repeatInterval`.
///
/// Pure and deterministic — time is injected, so it unit-tests without a clock. The app
/// feeds each pace sample and turns the returned `PaceAlert` into sound.
public struct PaceAlertMonitor {

    public enum PaceAlert: Equatable, Sendable {
        case tooSlow   // pace is slower than target by more than the threshold
        case tooFast   // pace is faster than target by more than the threshold
    }

    public struct Config: Equatable, Sendable {
        /// Half-width of the in-range band, in seconds per km. ±20 by default.
        public var thresholdSeconds: Double
        /// How often to re-beep while still out of range.
        public var repeatInterval: TimeInterval
        public init(thresholdSeconds: Double = 20, repeatInterval: TimeInterval = 30) {
            self.thresholdSeconds = thresholdSeconds
            self.repeatInterval = repeatInterval
        }
    }

    private enum Zone: Equatable { case inRange, slow, fast }

    public let config: Config
    private var zone: Zone = .inRange
    private var lastFiredAt: TimeInterval?

    public init(config: Config = Config()) { self.config = config }

    /// The currently-active deviation, or nil when in range / unknown. Unlike
    /// `evaluate`'s return (which is the momentary beep trigger), this reflects the
    /// standing state — what a persistent on-screen indicator should show.
    public var activeAlert: PaceAlert? {
        switch zone {
        case .inRange: return nil
        case .slow:    return .tooSlow
        case .fast:    return .tooFast
        }
    }

    /// Feed the latest pace; returns the alert to SOUND now, or nil.
    ///
    /// Pace is seconds-per-km, so a *larger* value is *slower*. A non-positive pace (or
    /// target) means "unknown" — GPS not ready / standing still — and is treated as
    /// in-range so nothing beeps and the band resets cleanly for the next real sample.
    ///
    /// Fires immediately on entering an out-of-range zone (and again immediately when
    /// switching directly from too-slow to too-fast), then every `repeatInterval` while
    /// the runner stays out of range.
    public mutating func evaluate(currentPaceSecPerKm pace: Double,
                                  targetPaceSecPerKm target: Double,
                                  now: TimeInterval) -> PaceAlert? {
        guard pace > 0, target > 0 else {
            zone = .inRange
            lastFiredAt = nil
            return nil
        }

        let delta = pace - target                 // > 0 means slower than target
        let newZone: Zone
        if delta > config.thresholdSeconds {
            newZone = .slow
        } else if delta < -config.thresholdSeconds {
            newZone = .fast
        } else {
            newZone = .inRange
        }
        let previousZone = zone
        zone = newZone

        switch newZone {
        case .inRange:
            lastFiredAt = nil
            return nil
        case .slow, .fast:
            let alert: PaceAlert = (newZone == .slow) ? .tooSlow : .tooFast
            if newZone != previousZone {           // just crossed in, or switched sides
                lastFiredAt = now
                return alert
            }
            if let last = lastFiredAt, now - last >= config.repeatInterval {
                lastFiredAt = now
                return alert
            }
            return nil
        }
    }
}
