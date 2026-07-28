import Foundation

/// A spoken coaching cue. Deliberately a small, closed set: a coach who talks
/// constantly is worse than none, and every cue interrupts music the runner chose.
public enum CoachCue: Sendable, Equatable {

    /// A kilometre (or mile) completed, with its pace and how it compared to target.
    case split(index: Int, paceSecPerKm: Double, deltaVsTargetSec: Double)
    /// Periodic "where you stand" against the goal pace.
    case goalPace(deltaSecPerKm: Double)
    /// Halfway on a distance goal: what the second half needs to be.
    case negativeSplit(firstHalfPaceSecPerKm: Double, targetSecondHalfPaceSecPerKm: Double)
    /// The distance goal is done.
    case finish(elapsedSeconds: Double, averagePaceSecPerKm: Double)

    /// What the voice says. Short by design — a runner is breathing hard and has
    /// music playing; a sentence they have to parse twice is a failed cue.
    public var spoken: String {
        switch self {
        case let .split(index, pace, delta):
            let comparison: String
            let seconds = Int(abs(delta).rounded())
            if seconds < 3 { comparison = "on target" }
            else if delta < 0 { comparison = "\(seconds) seconds fast" }
            else { comparison = "\(seconds) seconds slow" }
            return "Kilometre \(index). \(Self.pacePhrase(pace)). \(comparison)."

        case let .goalPace(delta):
            let seconds = Int(abs(delta).rounded())
            if seconds < 3 { return "Right on pace." }
            return delta > 0
                ? "\(seconds) seconds per kilometre behind. Lift it a little."
                : "\(seconds) seconds per kilometre ahead. Ease back."

        case let .negativeSplit(first, target):
            return "Halfway. First half \(Self.pacePhrase(first)). "
                 + "For a negative split, run the rest at \(Self.pacePhrase(target))."

        case let .finish(elapsed, pace):
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            return "Done. \(minutes) minutes \(seconds) seconds, "
                 + "averaging \(Self.pacePhrase(pace))."
        }
    }

    /// "5 minutes 30 per kilometre" — spoken, not the display's "5:30".
    static func pacePhrase(_ secPerKm: Double) -> String {
        guard secPerKm.isFinite, secPerKm > 0 else { return "unknown pace" }
        let total = Int(secPerKm.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return seconds == 0
            ? "\(minutes) minutes per kilometre"
            : "\(minutes) \(seconds < 10 ? "oh " : "")\(seconds) per kilometre"
    }
}

/// Decides WHEN to say something. Pure and deterministic: the app feeds it the same
/// live samples the loop gets and plays whatever comes back, so cue timing is unit
/// testable without audio, a device, or a run.
///
/// Three rules keep the coach additive rather than intrusive — the DJ is the product:
///   1. **Silence is the default.** Cues fire on real events (a split, the halfway
///      mark) or a long interval, never on a timer that chatters.
///   2. **Never during a transition.** The app reports when a track is changing and
///      the engine holds the cue until the crossfade is done, so coaching never
///      steps on the music it sits above.
///   3. **One at a time, with breathing room.** A minimum gap between cues, and a
///      split always outranks a routine pace check.
public struct CoachCueEngine {

    public struct Config: Sendable, Equatable {
        /// Announce a split every this many metres.
        public var splitMeters: Double = 1_000
        /// Minimum seconds between ANY two cues.
        public var minGapSeconds: Double = 45
        /// How often the routine goal-pace check may fire.
        public var goalPaceIntervalSeconds: Double = 300
        /// Don't nag about a delta smaller than this (s/km).
        public var goalPaceDeadband: Double = 4
        /// Ignore the first stretch — pace is noise until the runner settles.
        public var warmupSeconds: Double = 60
        public init() {}
    }

    /// Everything the engine needs about the run right now.
    public struct Sample: Sendable, Equatable {
        public let distanceMeters: Double
        public let elapsedSeconds: Double
        public let paceSecPerKm: Double
        public let targetPaceSecPerKm: Double
        /// Distance goal, if the runner set one — required for halfway/finish cues.
        public let goalMeters: Double?
        /// True while a track change is in flight. A cue here would talk over the
        /// crossfade, which is exactly what "additive, not instead of" forbids.
        public let isTransitioning: Bool

        public init(distanceMeters: Double, elapsedSeconds: Double, paceSecPerKm: Double,
                    targetPaceSecPerKm: Double, goalMeters: Double? = nil,
                    isTransitioning: Bool = false) {
            self.distanceMeters = distanceMeters
            self.elapsedSeconds = elapsedSeconds
            self.paceSecPerKm = paceSecPerKm
            self.targetPaceSecPerKm = targetPaceSecPerKm
            self.goalMeters = goalMeters
            self.isTransitioning = isTransitioning
        }
    }

    public var config: Config
    /// Off unless the runner turns it on. The DJ works with no coach at all.
    public var isEnabled: Bool

    private var splitsAnnounced = 0
    private var lastCueAt: Double = -.infinity
    private var lastGoalPaceAt: Double = -.infinity
    private var announcedHalfway = false
    private var announcedFinish = false
    private var lastSplitDistance: Double = 0
    private var lastSplitElapsed: Double = 0

    public init(config: Config = .init(), isEnabled: Bool = false) {
        self.config = config
        self.isEnabled = isEnabled
    }

    /// Feed one live sample; returns a cue to speak, or nil (the common case).
    public mutating func update(_ sample: Sample) -> CoachCue? {
        guard isEnabled else { return nil }

        // A split that lands mid-crossfade is still owed to the runner — hold it and
        // let it fire on the next sample rather than dropping it.
        guard !sample.isTransitioning else { return nil }
        guard sample.elapsedSeconds >= config.warmupSeconds else { return nil }
        guard sample.elapsedSeconds - lastCueAt >= config.minGapSeconds else { return nil }

        if let cue = finishCue(sample) { return emit(cue, at: sample.elapsedSeconds) }
        if let cue = splitCue(sample) { return emit(cue, at: sample.elapsedSeconds) }
        if let cue = halfwayCue(sample) { return emit(cue, at: sample.elapsedSeconds) }
        if let cue = goalPaceCue(sample) {
            lastGoalPaceAt = sample.elapsedSeconds
            return emit(cue, at: sample.elapsedSeconds)
        }
        return nil
    }

    /// Session end (or a manual stop): the closing cue, if a goal was in play.
    public mutating func flush(_ sample: Sample) -> CoachCue? {
        guard isEnabled, !announcedFinish, sample.distanceMeters > 0 else { return nil }
        announcedFinish = true
        return .finish(elapsedSeconds: sample.elapsedSeconds,
                       averagePaceSecPerKm: averagePace(sample))
    }

    // MARK: - Private

    private mutating func emit(_ cue: CoachCue, at elapsed: Double) -> CoachCue {
        lastCueAt = elapsed
        return cue
    }

    private mutating func splitCue(_ sample: Sample) -> CoachCue? {
        let due = Double(splitsAnnounced + 1) * config.splitMeters
        guard sample.distanceMeters >= due else { return nil }

        // Pace for THIS split, not the whole run — that's what "your last km" means.
        let splitDistance = sample.distanceMeters - lastSplitDistance
        let splitSeconds = sample.elapsedSeconds - lastSplitElapsed
        let pace = splitDistance > 0 ? splitSeconds / (splitDistance / 1_000) : sample.paceSecPerKm

        splitsAnnounced += 1
        lastSplitDistance = sample.distanceMeters
        lastSplitElapsed = sample.elapsedSeconds
        return .split(index: splitsAnnounced, paceSecPerKm: pace,
                      deltaVsTargetSec: pace - sample.targetPaceSecPerKm)
    }

    private mutating func halfwayCue(_ sample: Sample) -> CoachCue? {
        guard !announcedHalfway, let goal = sample.goalMeters, goal > 0,
              sample.distanceMeters >= goal / 2 else { return nil }
        announcedHalfway = true

        let firstHalf = averagePace(sample)
        // A negative split means the second half is faster. Ask for the pace that
        // brings the WHOLE run to target, floored so it never demands the impossible.
        let neededOverall = sample.targetPaceSecPerKm
        let secondHalf = max(firstHalf * 0.85, 2 * neededOverall - firstHalf)
        return .negativeSplit(firstHalfPaceSecPerKm: firstHalf,
                              targetSecondHalfPaceSecPerKm: secondHalf)
    }

    private mutating func finishCue(_ sample: Sample) -> CoachCue? {
        guard !announcedFinish, let goal = sample.goalMeters, goal > 0,
              sample.distanceMeters >= goal else { return nil }
        announcedFinish = true
        return .finish(elapsedSeconds: sample.elapsedSeconds,
                       averagePaceSecPerKm: averagePace(sample))
    }

    private func goalPaceCue(_ sample: Sample) -> CoachCue? {
        guard sample.elapsedSeconds - lastGoalPaceAt >= config.goalPaceIntervalSeconds,
              sample.paceSecPerKm > 0 else { return nil }
        let delta = sample.paceSecPerKm - sample.targetPaceSecPerKm
        guard abs(delta) >= config.goalPaceDeadband else { return nil }
        return .goalPace(deltaSecPerKm: delta)
    }

    private func averagePace(_ sample: Sample) -> Double {
        sample.distanceMeters > 0
            ? sample.elapsedSeconds / (sample.distanceMeters / 1_000)
            : sample.paceSecPerKm
    }
}
