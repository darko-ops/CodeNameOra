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

    let labelsByID: [String: String]

    private let tracks: [Track]
    private let provider: MusicProviderProtocol?
    private let targetPaceSecPerKm: Double
    private let targetCadence: Double

    private let source = PaceCadenceSource()
    private let playback = MediaPlayerPlaybackController()
    private var loop: LiveLoop?

    /// Hard ±20 s/km pace alarm: beeps (slow vs fast) over ducked music, repeating
    /// every 30 s while out of range. Separate from the engine's gentle music nudge.
    private var paceAlerts = PaceAlertMonitor()
    private let alertPlayer = PaceAlertPlayer()

    /// Behavioral learning loop: attribute the runner's pace response to the playing
    /// track, learn per-(track, mode) effectiveness, and feed it back into selection.
    private var attributor = PaceResponseAttributor()
    private let effStore = GRDBEffectivenessStore()

    /// Persists this run (session + pace log + track plays) so it shows on the You-tab
    /// dashboard / Goals / Sessions list — the same path the old flow used.
    private var recorder: LiveRunRecorder?
    private let sessionRepo = SessionRepository()
    /// Ignore accidental opens — only persist runs of at least this length.
    private let minRunSeconds = 30

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

    init(tracks: [Track], targetPaceSecPerKm: Double, provider: MusicProviderProtocol? = nil) {
        self.tracks = tracks
        self.provider = provider
        self.targetPaceSecPerKm = targetPaceSecPerKm
        targetCadence = CadenceModel().targetCadence(forPaceSecPerKm: targetPaceSecPerKm)
        labelsByID = Dictionary(tracks.map { ($0.id, "\($0.title) — \($0.artist)") },
                                uniquingKeysWith: { a, _ in a })
        feedback = FeedbackRouter(
            api: HTTPTrackTableClient(baseURL: LibrarySync.baseURL),
            preferences: GRDBPreferenceStore(),
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

    func start() {
        Task { @MainActor in
            // 1) Instant pool from the user's real (playable) tracks. No catalog here:
            //    catalog tracks have no playable audio, so they'd just be dead weight.
            //    Untagged tracks pick up their BPM from the enrichment cache (GetSongBPM)
            //    so they're tempo-matchable once the background lookup has run.
            let enriched = await EnrichedBPMStore().all()
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
                                                          catalog: [])
            let playable = initial.filter { UInt64($0.id) != nil }.count
            Self.log("""
                start: \(providerEntries.count) library tracks → initial pool \(initial.count) \
                (\(playable) playable, \(initial.count - playable) catalog) · \
                target \(Int(targetPaceSecPerKm))s/km
                """)
            let loop = LiveLoop(playback: playback, candidates: initial,
                                targetPaceSecPerKm: targetPaceSecPerKm, log: Self.log)
            self.loop = loop
            wire(loop)
            recorder = LiveRunRecorder(targetPaceSecPerKm: targetPaceSecPerKm,
                                       startedAt: Date(), tracks: tracks)
            // Prime the loop with what past runs learned, so even the FIRST pick this
            // session benefits from the runner's demonstrated response.
            await loop.updateEffectiveness(effStore.allByMode())
            source.start()
            self.state = await loop.start()
            await applyPreferenceWeights()   // carry over taste from past sessions

            // 2) Resolve identities (ISRC) + analyzable URLs from the provider, then
            //    resolve through the Global Track Table and upgrade the pool in place.
            Self.log("resolving \(providerEntries.count) tracks via Track Table…")
            let (entries, urlByID) = await enrichWithIdentity(providerEntries)
            let withISRC = entries.filter { $0.identity != nil }.count
            Self.log("identity: \(withISRC)/\(entries.count) have ISRC, \(urlByID.count) analyzable URLs")
            let upgraded = await resolvePool(entries: entries, urlByID: urlByID)
            await loop.updateCandidates(upgraded)
        }
    }

    func stop() {
        source.stop()
        paceAlert = nil
        // Close out the final track so its response is learned too.
        if let response = attributor.flush() {
            Task { await effStore.record(response) }
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

    private func resolvePool(entries: [LibraryEntry], urlByID: [String: URL]) async -> [TrackFacts] {
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
        let resolver = SessionPoolResolver(coordinator: coordinator, cache: cache, catalog: [])
        return await resolver.resolvedPool(entries: entries, targetCadence: targetCadence)
    }

    // MARK: - Loop callbacks

    private func wire(_ loop: LiveLoop) {
        source.onSample = { [weak self] cadence, pace in
            Task { @MainActor in
                guard let self else { return }
                let s = await loop.ingest(rawCadence: cadence, paceSecPerKm: pace)
                self.state = s
                // Hard pace-deviation alarm (±20 s/km). systemUptime is a monotonic
                // clock — correct for the 30 s repeat interval regardless of wall time.
                if let alert = self.paceAlerts.evaluate(
                    currentPaceSecPerKm: s.currentPaceSecPerKm,
                    targetPaceSecPerKm: s.targetPaceSecPerKm,
                    now: ProcessInfo.processInfo.systemUptime) {
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
                    await self.effStore.record(response)
                    await loop.updateEffectiveness(self.effStore.allByMode())
                }

                // Record the run for the dashboard (distance, pace log, track plays).
                self.recorder?.sample(paceSecPerKm: s.currentPaceSecPerKm,
                                      bpm: s.nowPlayingBPM ?? 0,
                                      trackID: s.nowPlayingTrackID, at: Date())
            }
        }
        playback.onAdvance = { [weak self] in
            let s = await loop.trackDidEnd()
            await MainActor.run { self?.state = s }
        }
    }
}
