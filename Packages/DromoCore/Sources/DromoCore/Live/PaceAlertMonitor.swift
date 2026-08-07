import Foundation

/// The pace-deviation alarm — a HARD ±threshold band around the target pace, distinct
/// from the engine's gentle music nudges (`SelectionEngine.Nudge`). When the runner
/// drifts outside the band, the app sounds a cue: one chime for too-slow, another for
/// too-fast. While still out of range, it re-fires every `repeatInterval`.
///
/// It stays silent until the runner has been inside the band at least once. Nobody is on
/// target in the first strides of a run, and an alarm that goes off before the runner has
/// found their pace is telling them something they already know — so the band arms on the
/// way in, not at the start line.
///
/// Pure and deterministic — time is injected, so it unit-tests without a clock. The app
/// feeds each pace sample and turns the returned `PaceAlert` into sound.
public struct PaceAlertMonitor {

    public enum PaceAlert: Equatable, Sendable {
        case tooSlow   // pace is slower than target by more than the threshold
        case tooFast   // pace is faster than target by more than the threshold
    }

    public struct Config: Equatable, Sendable {
        /// Half-width of the in-range band, in seconds per km. ±15 by default.
        public var thresholdSeconds: Double
        /// How often to re-sound the cue while still out of range.
        public var repeatInterval: TimeInterval
        public init(thresholdSeconds: Double = 15, repeatInterval: TimeInterval = 15) {
            self.thresholdSeconds = thresholdSeconds
            self.repeatInterval = repeatInterval
        }
    }

    private enum Zone: Equatable { case inRange, slow, fast }

    public let config: Config
    private var zone: Zone = .inRange
    private var lastFiredAt: TimeInterval?
    /// Set by the first genuine in-range sample, and never cleared: settling once is
    /// enough to say the runner knows what pace they are aiming for.
    private var isArmed = false

    public init(config: Config = Config()) { self.config = config }

    /// Whether the runner has reached the band yet. Until they have, the monitor is
    /// silent whatever the pace does.
    public var isActive: Bool { isArmed }

    /// The currently-active deviation, or nil when in range / unknown / not yet armed.
    /// Unlike `evaluate`'s return (which is the momentary sound trigger), this reflects
    /// the standing state — what a persistent on-screen indicator should show. It stays
    /// nil before arming so the screen doesn't shout what the speaker is staying quiet
    /// about.
    public var activeAlert: PaceAlert? {
        guard isArmed else { return nil }
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
    /// in-range so nothing sounds and the band resets cleanly for the next real sample.
    /// It does not arm the monitor: "no reading" is not the same as "on pace".
    ///
    /// Once armed, fires immediately on leaving the band (and again immediately when
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
            isArmed = true                         // reached the band — alarms are live
            lastFiredAt = nil
            return nil
        case .slow, .fast:
            guard isArmed else { return nil }      // still finding their pace
            let alert: PaceAlert = (newZone == .slow) ? .tooSlow : .tooFast
            if newZone != previousZone {           // just crossed out, or switched sides
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
