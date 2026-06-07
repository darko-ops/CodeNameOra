import Foundation

/// What the runner's state asks for right now — shared by the selection engine (which
/// weights candidates by it) and the response attributor (which keys learned
/// effectiveness by it). A track that drives you in `push` may be useless in `settle`,
/// so behavioral learning is kept per-mode, not global.
public enum PaceMode: String, Sendable, Equatable, CaseIterable {
    case push      // behind pace → need to speed up
    case hold      // on pace → lock the groove
    case settle    // ahead / cooling down → ease off

    /// `gap` = targetCadence − currentCadence (spm). Behind (gap > tol) → push;
    /// ahead (gap < −tol) → settle; within the band → hold.
    public init(gap: Double, onPaceTolerance: Double) {
        if gap > onPaceTolerance { self = .push }
        else if gap < -onPaceTolerance { self = .settle }
        else { self = .hold }
    }
}

/// A finalized observation of how the runner responded while one track played — the
/// ground-truth signal that beats any audio feature. `reward` is the reduction in the
/// absolute cadence gap over the play (spm): positive = the track helped close the gap
/// (drove you up when behind, or eased you down when ahead); negative = it didn't.
public struct TrackResponse: Equatable, Sendable {
    public let trackID: String
    public let mode: PaceMode
    public let reward: Double
    public let samples: Int

    public init(trackID: String, mode: PaceMode, reward: Double, samples: Int) {
        self.trackID = trackID
        self.mode = mode
        self.reward = reward
        self.samples = samples
    }
}

/// Attributes a stretch of cadence samples to the track that was playing, emitting a
/// `TrackResponse` when the track changes. Pure and deterministic — the app feeds it
/// the same samples it feeds the live loop, and routes the responses to the learner.
public struct PaceResponseAttributor {

    public struct Config: Sendable, Equatable {
        /// Band (spm) used to classify the play's mode from its opening gap. Match the
        /// engine's `onPaceTolerance` so learning is keyed to the mode that was acted on.
        public var onPaceTolerance: Double = 4
        /// Ignore ultra-short plays (instant skips) — too little signal to attribute.
        public var minSamples: Int = 3
        public init() {}
    }

    public let config: Config
    private var currentTrackID: String?
    private var startGap: Double = 0
    private var lastGap: Double = 0
    private var startMode: PaceMode = .hold
    private var count: Int = 0

    public init(config: Config = .init()) { self.config = config }

    /// Feed one live sample. Returns the PREVIOUS track's finalized response when the
    /// playing track just changed (so the caller can learn from it), else nil.
    public mutating func observe(trackID: String?, targetCadence: Double,
                                 currentCadence: Double) -> TrackResponse? {
        let gap = targetCadence - currentCadence

        if trackID != currentTrackID {
            let emitted = finalize()                 // close out the previous track
            currentTrackID = trackID
            startGap = gap
            lastGap = gap
            startMode = PaceMode(gap: gap, onPaceTolerance: config.onPaceTolerance)
            count = (trackID == nil) ? 0 : 1
            return emitted
        }

        if trackID != nil {
            lastGap = gap
            count += 1
        }
        return nil
    }

    /// Close out the current track (call on session end). Returns its response, if any.
    public mutating func flush() -> TrackResponse? {
        let emitted = finalize()
        currentTrackID = nil
        count = 0
        return emitted
    }

    private func finalize() -> TrackResponse? {
        guard let id = currentTrackID, count >= config.minSamples else { return nil }
        let reward = abs(startGap) - abs(lastGap)    // + = gap closed while it played
        return TrackResponse(trackID: id, mode: startMode, reward: reward, samples: count)
    }
}

/// Turns a `TrackResponse.reward` into a 0…1 effectiveness and folds it into the
/// running per-(track, mode) estimate via an EMA. Pure; the store owns one of these.
public struct EffectivenessLearner: Sendable {

    public struct Config: Sendable, Equatable {
        /// EMA weight on each new observation (0…1). Higher = adapts faster, noisier.
        public var learningRate: Double = 0.3
        /// The gap-closing (spm) that maps to a near-maximal signal. ±this → ~1 / ~0.
        public var rewardScale: Double = 8
        /// Effectiveness with no data (and the EMA's starting point).
        public var neutral: Double = 0.5
        public init() {}
    }

    public let config: Config
    public init(config: Config = .init()) { self.config = config }

    /// Map a reward (Δ|gap| spm) to 0…1, centered at `neutral`.
    public func rewardScore(_ reward: Double) -> Double {
        let s = config.neutral + reward / (2 * config.rewardScale)
        return min(1, max(0, s))
    }

    /// EMA-update a track's effectiveness toward the new observation.
    public func updated(previous: Double?, reward: Double) -> Double {
        let prev = previous ?? config.neutral
        return prev + config.learningRate * (rewardScore(reward) - prev)
    }
}
