import Foundation
import SwiftUI
import os
import DromoCore

/// Drives the Phase-5 live loop with the Phase-3 sync fully wired in. The candidate
/// pool is built the architecture-correct way: the run starts instantly on a
/// provider+catalog pool, then — in the background — each track's identity (ISRC via
/// the provider's analyzable asset URL) is resolved against the Global Track Table
/// (lookup-first, analyze-on-miss), and the upgraded pool is swapped in.
@MainActor
final class LiveSessionViewModel: ObservableObject {

    @Published private(set) var state: LoopState

    /// Standing pace-deviation state for the HUD overlay (nil = on pace / unknown).
    @Published private(set) var paceAlert: PaceAlertMonitor.PaceAlert?

    /// Wall-clock elapsed for the HUD's TIME readout (frozen while paused).
    @Published private(set) var elapsedSeconds: Double = 0

    /// How much of the runner's OWN library this session can pace to — drives the
    /// "from your library" story as enrichment fills coverage in over time.
    @Published private(set) var coverage = LibraryCoverage(total: 0, tagged: 0)

    /// Origin per track id, so the HUD can badge what came from the runner's library.
    private var origins: [String: TrackOrigin] = [:]

    /// Finalized responses from THIS run — the evidence behind the post-run
    /// "What moved you". Same objects the learner consumed, so the summary and the
    /// learner can never tell different stories about the same run.
    @Published private(set) var runResponses: [TrackResponse] = []

    /// Why the engine chose what's playing, for the HUD's "why this track?".
    @Published private(set) var nowPlayingReason: SelectionEngine.Reason?

    /// Where the now-playing track came from (defaults to the runner's own music).
    var nowPlayingOrigin: TrackOrigin {
        guard let id = state.nowPlayingTrackID else { return .library }
        return origins[id] ?? .library
    }
    /// Pause state — freezes the loop, the clock, and playback (HUD Pause button).
    @Published private(set) var isPaused = false

    let labelsByID: [String: String]
    /// Title/artist/BPM for the now-playing card, keyed by track id.
    let tracksByID: [String: Track]

    private var clock: Timer?

    private let tracks: [Track]
    private let provider: MusicProviderProtocol?
    private let targetPaceSecPerKm: Double
    /// Optional distance goal (meters) — drives the finishing-line kick.
    private let targetDistanceMeters: Double?
    private let targetCadence: Double

    private let source = PaceCadenceSource()
    /// Routes catalog ids to bundled audio and library ids to the system player, so
    /// the loop sees one playback surface whether or not the catalog is stocked.
    private let playback = CatalogPlaybackController()
    private var loop: LiveLoop?

    /// Hard ±20 s/km pace alarm: beeps (slow vs fast) over ducked music, repeating
    /// every 30 s while out of range. Separate from the engine's gentle music nudge.
    private var paceAlerts = PaceAlertMonitor()
    private let alertPlayer = PaceAlertPlayer()

    /// Optional coach layer (Phase 7): splits, goal-pace checks and negative-split
    /// guidance, spoken over ducked music. Off unless the runner turned it on — the
    /// DJ is the product and works with nothing enabled here.
    private var coach = CoachCueEngine(isEnabled: CoachVoice.isEnabled)
    private let coachVoice = CoachVoice()
    /// The track id the loop was playing at the previous sample — a change means a
    /// transition is in flight, and the coach must not speak across it.
    private var lastCoachTrackID: String?

    /// Behavioral learning loop: attribute the runner's pace response to the playing
    /// track, learn per-(track, mode) effectiveness, and feed it back into selection.
    private var attributor = PaceResponseAttributor()
    /// Learning is collective across duplicate copies of a recording: responses and
    /// taste recorded through any app's copy attach to the recording itself.
    private let aliases: RecordingAliases
    private let effStore: CollectiveEffectivenessStore

    /// Persists this run (session + pace log + track plays) so it shows on the You-tab
    /// dashboard / Goals / Sessions list — the same path the old flow used.
    private var recorder: LiveRunRecorder?
    private let sessionRepo = SessionRepository()
    /// Ignore accidental opens — only persist runs of at least this length.
    private let minRunSeconds = 30

    /// Natural-fatigue context: softens the engine's push when the runner is genuinely
    /// tiring (vs lazy-slow), estimated from the live cadence stream.
    private var fatigueEstimator = FatigueEstimator()
    private var lastLoggedFatigue = 1.0
    private var inFinishingKick = false

    /// Debug sink — shows in Xcode console and Console.app (subsystem com.daed.dromo,
    /// category "livesession"). Sendable so it can be handed to the LiveLoop actor.
    private static let logger = Logger(subsystem: "com.daed.dromo", category: "livesession")
    private static let log: @Sendable (String) -> Void = { msg in
        logger.notice("\(msg, privacy: .public)")   // .notice shows in Console.app by default
        print("🏃 [Dromo] \(msg)")
    }

    // Phase-6 feedback: subjective (taste) → private store; objective → Track Table.
    private let feedback: FeedbackRouter
    private let factsCache = GRDBTrackFactsCache()
    private var identityByLocalID: [String: IdentityKey] = [:]

    init(tracks: [Track], targetPaceSecPerKm: Double, targetDistanceMeters: Double? = nil,
         provider: MusicProviderProtocol? = nil, aliases: RecordingAliases = RecordingAliases()) {
        self.tracks = tracks
        self.provider = provider
        self.aliases = aliases
        self.effStore = CollectiveEffectivenessStore(base: GRDBEffectivenessStore(),
                                                     aliases: aliases)
        self.targetPaceSecPerKm = targetPaceSecPerKm
        self.targetDistanceMeters = targetDistanceMeters
        targetCadence = CadenceModel().targetCadence(forPaceSecPerKm: targetPaceSecPerKm)
        labelsByID = Dictionary(tracks.map { ($0.id, "\($0.title) — \($0.artist)") },
                                uniquingKeysWith: { a, _ in a })
        tracksByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        feedback = FeedbackRouter(
            api: HTTPTrackTableClient(baseURL: LibrarySync.baseURL),
            preferences: CollectivePreferenceStore(base: GRDBPreferenceStore(),
                                                   aliases: aliases),
            clientID: DeviceID.current)
        state = LoopState(currentCadence: 0, targetCadence: targetCadence,
                          currentPaceSecPerKm: targetPaceSecPerKm,
                          targetPaceSecPerKm: targetPaceSecPerKm)
    }

    // MARK: - Feedback (wired to the HUD)

    /// Subjective: "I like this" → private per-user store; re-weights selection live.
    func like() {
        guard let id = state.nowPlayingTrackID else { return }
        Task {
            await feedback.reportSubjective(.liked, trackID: id)
            await applyPreferenceWeights()
        }
    }

    /// Subjective skip → private store, re-weight, and advance to the next track now.
    func skip() {
        guard let id = state.nowPlayingTrackID else { return }
        Task { @MainActor in
            await feedback.reportSubjective(.skipped, trackID: id)
            await applyPreferenceWeights()
            if let loop { state = await loop.trackDidEnd() }
        }
    }

    /// Objective: "this isn't the tempo" → Global Track Table correction path. Only
    /// reaches the table for tracks resolved via identity (ISRC); a no-op otherwise.
    func flagOffTempo() {
        guard let id = state.nowPlayingTrackID, let identity = identityByLocalID[id] else { return }
        Task {
            guard let serverID = await factsCache.get(identity)?.id else { return }
            await feedback.reportObjective(.feltOffTempo(observedBPM: nil), trackID: serverID)
        }
    }

    private func applyPreferenceWeights() async {
        guard let loop else { return }
        await loop.updatePreferences(await feedback.preferenceWeights())
    }

    /// Pause/resume the run: freezes the clock + loop ingestion and pauses playback.
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            playback.pause()
            coachVoice.stop()        // no coaching into a paused run
            paceAlert = nil          // don't leave an alarm hanging while stopped
        } else {
            playback.resume()
        }
    }

    func start() {
        // Analysis must never compete with a run for CPU or battery (Phase 4 gate).
        TrackContributor.isSessionActive = true
        Task { @MainActor in
            // 1) Instant pool: the user's real (playable) tracks PLUS whatever of
            //    Dromo's catalog is actually stocked with audio in this build, so a
            //    library with no usable tempo still has something to pace to.
            //    Untagged tracks pick up their BPM from the enrichment cache (GetSongBPM)
            //    so they're tempo-matchable once the background lookup has run.
            // Expanded through the alias map so a BPM cached under the recording id
            // (looked up via ANY app's copy) reaches whichever copy is in this pool.
            let enriched = aliases.expanded(await EnrichedBPMStore().all())
            let providerEntries = tracks.map { track -> LibraryEntry in
                let bpm = track.bpm > 0 ? track.bpm : (enriched[track.id] ?? 0)
                return LibraryEntry(localID: track.id, identity: nil, providerBPM: bpm,
                                    energy: track.energyLevel,
                                    durationMs: track.durationSeconds * 1_000)
            }
            let known = providerEntries.filter { ($0.providerBPM ?? 0) > 0 }.count
            Self.log("enrichment cache: \(enriched.count) BPMs; \(known)/\(providerEntries.count) pool tracks have BPM")
            let initial = SessionPoolResolver.initialPool(entries: providerEntries,
                                                          targetCadence: targetCadence,
                                                          catalog: CatalogLibrary.shared.stockedTracks)
            coverage = LibraryCoverage.measure(pool: initial)
            origins = initial.origins
            Self.log("""
                start: \(providerEntries.count) library tracks → initial pool \(initial.count) \
                (\(initial.libraryTracks.count) yours, \(initial.catalogTracks.count) catalog, \
                \(coverage.tagged) tempo-matched) · target \(Int(targetPaceSecPerKm))s/km
                """)
            let loop = LiveLoop(playback: playback, candidates: initial.facts,
                                origins: initial.origins,
                                targetPaceSecPerKm: targetPaceSecPerKm, log: Self.log)
            self.loop = loop
            wire(loop)
            recorder = LiveRunRecorder(targetPaceSecPerKm: targetPaceSecPerKm,
                                       startedAt: Date(), tracks: tracks)
            // Prime the loop with what past runs learned, so even the FIRST pick this
            // session benefits from the runner's demonstrated response.
            await loop.updateEffectiveness(effStore.allByMode())
            source.start()
            startClock()
            self.state = await loop.start()
            await applyPreferenceWeights()   // carry over taste from past sessions

            // 2) Resolve identities (ISRC) + analyzable URLs from the provider, then
            //    resolve through the Global Track Table and upgrade the pool in place.
            Self.log("resolving \(providerEntries.count) tracks via Track Table…")
            let (entries, urlByID) = await enrichWithIdentity(providerEntries)
            let withISRC = entries.filter { $0.identity != nil }.count
            Self.log("identity: \(withISRC)/\(entries.count) have ISRC, \(urlByID.count) analyzable URLs")
            let upgraded = await resolvePool(entries: entries, urlByID: urlByID)
            coverage = LibraryCoverage.measure(pool: upgraded)
            origins = upgraded.origins
            await loop.updateCandidates(upgraded)
        }
    }

    /// 1 Hz clock for the HUD's TIME readout — ticks only while running (not paused).
    private func startClock() {
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    func stop() {
        TrackContributor.isSessionActive = false
        source.stop()
        clock?.invalidate()
        clock = nil
        paceAlert = nil
        // Close out with the run's summary line, then fall silent — a coach that keeps
        // talking to someone who has stopped is just noise.
        if let cue = coach.flush(CoachCueEngine.Sample(
            distanceMeters: recorder?.distanceMeters ?? 0,
            elapsedSeconds: elapsedSeconds,
            paceSecPerKm: state.currentPaceSecPerKm,
            targetPaceSecPerKm: state.targetPaceSecPerKm)) {
            coachVoice.speak(cue)
        } else {
            coachVoice.stop()
        }
        // Close out the final track so its response is learned too.
        if let response = attributor.flush() {
            runResponses.append(response)
            Task { [effStore] in await effStore.record(response) }
        }
        // Persist the run (unless it was an accidental, too-short open).
        if var recorder {
            let session = recorder.finish(at: Date())
            self.recorder = nil
            if session.elapsedSeconds >= minRunSeconds {
                let repo = sessionRepo
                Task {
                    try? await repo.save(session)
                    // Tell the You-tab dashboard to refresh, even if it's already on screen.
                    await MainActor.run {
                        NotificationCenter.default.post(name: .dromoSessionSaved, object: nil)
                    }
                }
            }
        }
    }

    // MARK: - Resolution

    /// Reads each track's ISRC from its analyzable URL (cheap, metadata only). Tracks
    /// without a URL/ISRC keep `identity == nil` and fall back to provider BPM —
    /// fingerprint-based identity for those is a deferred (decode-heavy) optimization.
    private func enrichWithIdentity(
        _ entries: [LibraryEntry]
    ) async -> (entries: [LibraryEntry], urls: [String: URL]) {
        guard let provider else { return (entries, [:]) }
        var enriched: [LibraryEntry] = []
        var urls: [String: URL] = [:]
        for entry in entries {
            var identity: IdentityKey?
            if let url = await provider.analyzableURL(forTrackID: entry.localID) {
                urls[entry.localID] = url
                if let isrc = await ISRCReader.isrc(from: url) {
                    identity = IdentityKey(isrc: isrc)
                }
            }
            // DRM / cloud fallback: no local file or tag → resolve ISRC from the
            // Apple Music catalog (playbackStoreID → Song.isrc). This is what lets a
            // streaming-only library key into the Global Track Table.
            if identity == nil, let isrc = await provider.catalogISRC(forTrackID: entry.localID) {
                identity = IdentityKey(isrc: isrc)
            }
            if let identity { identityByLocalID[entry.localID] = identity }   // for objective feedback
            enriched.append(LibraryEntry(
                localID: entry.localID, identity: identity, providerBPM: entry.providerBPM,
                energy: entry.energy, durationMs: entry.durationMs))
        }
        return (enriched, urls)
    }

    private func resolvePool(entries: [LibraryEntry], urlByID: [String: URL]) async -> SessionPool {
        let analyzer = TrackAnalyzer()
        let cache = GRDBTrackFactsCache()
        // analyze-on-miss decodes the track's URL on-device; only the numeric result
        // leaves the device (ARCHITECTURE §4).
        let coordinator = LibrarySyncCoordinator(
            api: HTTPTrackTableClient(baseURL: LibrarySync.baseURL), cache: cache
        ) { item in
            guard let url = urlByID[item.localID] else { return nil }
            return await analyzer.analyze(url: url)?.result
        }
        let resolver = SessionPoolResolver(coordinator: coordinator, cache: cache,
                                           catalog: CatalogLibrary.shared.stockedTracks)
        return await resolver.resolvedPool(entries: entries, targetCadence: targetCadence)
    }

    // MARK: - Loop callbacks

    private func wire(_ loop: LiveLoop) {
        source.onSample = { [weak self] cadence, pace in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isPaused else { return }   // frozen while paused
                let s = await loop.ingest(rawCadence: cadence, paceSecPerKm: pace)
                self.state = s
                let now = ProcessInfo.processInfo.systemUptime   // monotonic clock

                // Hard pace-deviation alarm (±20 s/km), repeating every 30 s while out.
                if let alert = self.paceAlerts.evaluate(
                    currentPaceSecPerKm: s.currentPaceSecPerKm,
                    targetPaceSecPerKm: s.targetPaceSecPerKm,
                    now: now) {
                    self.alertPlayer.play(alert)
                }
                // Standing state drives the HUD overlay (beep is the momentary trigger).
                self.paceAlert = self.paceAlerts.activeAlert

                // Behavioral learning: attribute this sample to the playing track. On a
                // track change, persist the finished track's response and feed the
                // freshly-learned effectiveness back so the NEXT pick uses it.
                if let response = self.attributor.observe(
                    trackID: s.nowPlayingTrackID,
                    targetCadence: s.targetCadence,
                    currentCadence: s.currentCadence) {
                    self.runResponses.append(response)
                    await self.effStore.record(response)
                    await loop.updateEffectiveness(self.effStore.allByMode())
                }
                self.nowPlayingReason = await loop.lastReason

                // Record the run for the dashboard (distance, pace log, track plays).
                self.recorder?.sample(paceSecPerKm: s.currentPaceSecPerKm,
                                      bpm: s.nowPlayingBPM ?? 0,
                                      trackID: s.nowPlayingTrackID, at: Date())

                // Coach layer. `isTransitioning` is true on the sample where the track
                // changed, so a cue can never land on a crossfade; the engine holds it
                // for the next second instead of dropping it.
                let changed = s.nowPlayingTrackID != self.lastCoachTrackID
                self.lastCoachTrackID = s.nowPlayingTrackID
                if let cue = self.coach.update(CoachCueEngine.Sample(
                    distanceMeters: self.recorder?.distanceMeters ?? 0,
                    elapsedSeconds: self.elapsedSeconds,
                    paceSecPerKm: s.currentPaceSecPerKm,
                    targetPaceSecPerKm: s.targetPaceSecPerKm,
                    goalMeters: self.targetDistanceMeters,
                    isTransitioning: changed)) {
                    self.coachVoice.speak(cue)
                }

                // Natural-fatigue context: estimate from the cadence stream and feed the
                // coefficient to the loop, so the next selection softens its push when
                // the runner is genuinely tiring rather than fighting them with fast music.
                self.fatigueEstimator.ingest(now: now, cadence: s.currentCadence,
                                             gap: s.targetCadence - s.currentCadence)
                var fatigue = self.fatigueEstimator.coefficient(now: now)

                // Finishing-line kick: in the last 10% of a distance goal, override the
                // fatigue softening and give a full push — the one moment aggressive
                // music actually helps. (Needs GPS distance; indoor runs won't trigger.)
                if let goal = self.targetDistanceMeters, goal > 0,
                   let dist = self.recorder?.distanceMeters, dist >= goal * 0.9 {
                    fatigue = 1.0
                    if !self.inFinishingKick {
                        self.inFinishingKick = true
                        Self.log("finishing kick — final 10% of \(Int(goal)) m, full push")
                    }
                }

                await loop.updateFatigue(fatigue)
                if abs(fatigue - self.lastLoggedFatigue) >= 0.1 {
                    Self.log("fatigue coefficient \(String(format: "%.2f", fatigue))")
                    self.lastLoggedFatigue = fatigue
                }
            }
        }
        playback.onAdvance = { [weak self] in
            let s = await loop.trackDidEnd()
            await MainActor.run { self?.state = s }
        }
    }
}
