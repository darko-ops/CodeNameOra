import Foundation

/// The HUD-facing snapshot of the live session (Phase 5). Everything the lock-screen
/// and Watch HUD need: current vs target pace, the nudge, and now-playing + its BPM.
public struct LoopState: Sendable, Equatable {
    public var nowPlayingTrackID: String?
    public var nowPlayingBPM: Double?
    public var nudge: SelectionEngine.Nudge
    public var currentCadence: Double
    public var targetCadence: Double
    public var currentPaceSecPerKm: Double
    public var targetPaceSecPerKm: Double

    public init(nowPlayingTrackID: String? = nil, nowPlayingBPM: Double? = nil,
                nudge: SelectionEngine.Nudge = .hold,
                currentCadence: Double, targetCadence: Double,
                currentPaceSecPerKm: Double, targetPaceSecPerKm: Double) {
        self.nowPlayingTrackID = nowPlayingTrackID
        self.nowPlayingBPM = nowPlayingBPM
        self.nudge = nudge
        self.currentCadence = currentCadence
        self.targetCadence = targetCadence
        self.currentPaceSecPerKm = currentPaceSecPerKm
        self.targetPaceSecPerKm = targetPaceSecPerKm
    }
}

/// Plays the engine-chosen tracks. Abstracted so the live loop is testable without
/// MusicKit. `play` returns false when a track can't be played (unavailable /
/// unanalyzed) so the loop can skip it.
public protocol PlaybackControlling: Sendable {
    func play(trackID: String) async -> Bool
}

/// The live loop (Phase 5): sense → decide (Phase-4 engine) → play → HUD, hands-free.
///
/// Push-driven and side-effect-light: the app feeds smoothed sensor samples via
/// `ingest`, signals song boundaries via `trackDidEnd`, and the loop calls the
/// injected `PlaybackControlling`. It does NOT re-implement selection — it delegates
/// to `SelectionEngine`. Every method returns the new `LoopState` for the HUD.
public actor LiveLoop {

    public struct Config: Sendable {
        /// How many unavailable tracks to skip past before giving up on a selection.
        public var maxSkipRetries = 5
        public init() {}
    }

    private var engine: SelectionEngine
    private let playback: any PlaybackControlling
    private var candidates: [TrackFacts]
    private var smoother: CadenceSmoother
    private var preferences: [String: Double]
    /// Learned behavioral effectiveness, per mode: [mode: [trackID: 0…1]]. Selection
    /// uses the sub-map for the mode in effect at pick time.
    private var effectivenessByMode: [PaceMode: [String: Double]] = [:]
    private let config: Config
    private let targetCadence: Double

    public private(set) var state: LoopState

    /// Optional debug sink — the app routes this to os.Logger / print so a device run
    /// shows exactly what the loop is doing while it "searches for a track".
    private let log: (@Sendable (String) -> Void)?

    public init(
        engine: SelectionEngine = .init(),
        playback: any PlaybackControlling,
        candidates: [TrackFacts],
        targetPaceSecPerKm: Double,
        cadenceModel: CadenceModel = .init(),
        smoother: CadenceSmoother = .init(),
        preferences: [String: Double] = [:],
        config: Config = .init(),
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.engine = engine
        self.playback = playback
        self.candidates = candidates
        self.smoother = smoother
        self.preferences = preferences
        self.config = config
        self.log = log
        let target = cadenceModel.targetCadence(forPaceSecPerKm: targetPaceSecPerKm)
        self.targetCadence = target
        self.state = LoopState(
            // currentCadence seeds to target so the nudge starts neutral (HOLD) until
            // real cadence arrives. currentPace seeds to 0 (unknown) so the HUD shows
            // "--:--" rather than a misleading value identical to the target.
            currentCadence: target, targetCadence: target,
            currentPaceSecPerKm: 0, targetPaceSecPerKm: targetPaceSecPerKm)
    }

    /// Begin the session: choose and play the first track.
    @discardableResult
    public func start() async -> LoopState {
        log?("start: pool=\(candidates.count) tracks, targetCadence=\(Int(targetCadence))")
        await selectAndPlay()
        return state
    }

    /// Feed a live sensor sample (~1 Hz). Updates pace/cadence + the HUD nudge, but
    /// does NOT switch tracks — switches happen on song boundaries (`trackDidEnd`).
    @discardableResult
    public func ingest(rawCadence: Double, paceSecPerKm: Double) async -> LoopState {
        let smoothed = smoother.add(rawCadence)
        state.currentCadence = smoothed
        state.currentPaceSecPerKm = paceSecPerKm
        state.nudge = engine.updateNudge(targetCadence: targetCadence, currentCadence: smoothed)
        return state
    }

    /// The current track ended — pick and play the next one (boundary-aligned switch).
    @discardableResult
    public func trackDidEnd() async -> LoopState {
        await selectAndPlay()
        return state
    }

    /// Replace the candidate pool mid-session (preserving nudge + recently-played
    /// state). Phase-3 resolution runs in the background and grows coverage; the
    /// session starts immediately on a provider/catalog pool and upgrades in place.
    public func updateCandidates(_ newCandidates: [TrackFacts]) {
        candidates = newCandidates
        log?("pool updated → \(newCandidates.count) tracks "
             + "(\(newCandidates.filter { $0.bpm > 0 }.count) with known BPM)")
    }

    /// Update the per-user taste weights mid-session, so likes/skips (Phase 6 A2)
    /// steer subsequent selections live.
    public func updatePreferences(_ newPreferences: [String: Double]) {
        preferences = newPreferences
    }

    /// Update the learned behavioral effectiveness (per mode) mid-session, so what the
    /// runner's response taught us steers the very next selection.
    public func updateEffectiveness(_ byMode: [PaceMode: [String: Double]]) {
        effectivenessByMode = byMode
    }

    private func selectAndPlay() async {
        var skipped = 0
        // Keep trying down the ranked pool until something actually plays. (Don't cap
        // at a few retries — unplayable candidates, e.g. catalog tracks with no audio,
        // could otherwise starve a fully-playable real library.)
        while true {
            // Behavioral effectiveness is keyed per mode; pick the sub-map for the mode
            // in effect right now (same classification the engine will use).
            let mode = PaceMode(gap: targetCadence - state.currentCadence,
                                onPaceTolerance: engine.config.onPaceTolerance)
            guard let decision = engine.selectNext(
                targetCadence: targetCadence,
                currentCadence: state.currentCadence,
                candidates: candidates,
                preferences: preferences,
                effectiveness: effectivenessByMode[mode] ?? [:]
            ) else {
                state.nowPlayingTrackID = nil
                log?("⚠️ no playable track — gave up after skipping \(skipped) "
                     + "(pool now \(candidates.count))")
                return
            }

            log?("trying \(decision.trackID) (\(Int(decision.effectiveBPM)) BPM)…")
            if await playback.play(trackID: decision.trackID) {
                state.nowPlayingTrackID = decision.trackID
                state.nowPlayingBPM = decision.effectiveBPM
                state.nudge = decision.nudge
                log?("▶️ playing \(decision.trackID) after \(skipped) skips")
                return
            }

            // Unplayable — drop it and try the next best candidate.
            log?("⏭️ skip (unplayable) \(decision.trackID)")
            candidates.removeAll { $0.id == decision.trackID }
            skipped += 1
        }
    }
}
