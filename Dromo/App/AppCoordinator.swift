import SwiftUI
import DromoCore

/// One connected music service: its live provider, the library it contributed, and
/// whether the runner currently has it toggled into the unified library. Connections
/// are retained even while toggled out — off means "leave my mix", not "disconnect".
struct ConnectedMusicSource: Identifiable {
    let choice: AppCoordinator.ProviderChoice
    let provider: MusicProviderProtocol
    var tracks: [Track]
    /// Why tempo may be missing for this source (surfaced with the library, per source).
    var note: String?
    var isEnabled: Bool

    var id: String { choice.rawValue }
}

/// Top-level navigation + shared state for the flow:
/// Auth (create account / sign in) → Setup (main tabs, with a one-time "add your
/// music" popup) → Active → Summary.
@MainActor
final class AppCoordinator: ObservableObject {

    enum Screen: Equatable {
        case auth
        case setup
        case session
        case summary
    }

    enum ProviderChoice: String, CaseIterable {
        case appleMusic = "Apple Music"
        case spotify = "Spotify"

        var trackProvider: Track.MusicProvider {
            switch self {
            case .appleMusic: return .appleMusic
            case .spotify: return .spotify
            }
        }
    }

    /// Local mock auth (swappable for a real backend behind the same surface).
    let account = AccountStore()

    /// Start signed-in if a previous session was persisted; otherwise show auth.
    @Published private(set) var screen: Screen

    /// One-time "Add your music" popup, presented over the tabs right after sign-in.
    @Published var showingMusicSetup = false

    init() {
        screen = account.isSignedIn ? .setup : .auth
        Task { await restoreConnectedSources() }
    }

    /// True while the first restore is in flight, so the UI can say "reconnecting"
    /// rather than "nothing connected".
    @Published private(set) var isRestoringSources = false

    /// Reconnect services the runner already authorized, without prompting.
    ///
    /// Authorizations outlive the process — Spotify's tokens sit in the Keychain, and
    /// the media-library grant is remembered by the system — but `sources` is in-memory
    /// only, so nothing here used to survive a relaunch. Every launch presented as
    /// "no music connected" and asked the runner to sign in again, discarding a
    /// perfectly good token in the process.
    private func restoreConnectedSources() async {
        isRestoringSources = true
        defer { isRestoringSources = false }

        // Only services the runner actually added. An authorization on its own doesn't
        // mean they connected anything: the media-library grant is a system permission
        // that can already be in place, and restoring on that alone silently added an
        // Apple Music source nobody asked for — which then suppressed the "add your
        // music" prompt, because something was technically connected.
        for choice in storedConnected() where !sources.contains(where: { $0.choice == choice }) {
            let provider = makeProvider(for: choice)
            guard await provider.isAuthorized else { continue }
            _ = await connect(choice, using: provider)
        }
    }

    // MARK: - Which services the runner connected

    private static let connectedSourcesKey = "music.sources.connected"

    private func storedConnected() -> [ProviderChoice] {
        (UserDefaults.standard.stringArray(forKey: Self.connectedSourcesKey) ?? [])
            .compactMap(ProviderChoice.init(rawValue:))
    }

    private func rememberConnected(_ choice: ProviderChoice) {
        var stored = storedConnected().map(\.rawValue)
        guard !stored.contains(choice.rawValue) else { return }
        stored.append(choice.rawValue)
        UserDefaults.standard.set(stored, forKey: Self.connectedSourcesKey)
    }

    private func forgetConnected(_ choice: ProviderChoice) {
        let stored = storedConnected().map(\.rawValue).filter { $0 != choice.rawValue }
        UserDefaults.standard.set(stored, forKey: Self.connectedSourcesKey)
    }

    /// Every connected service. Connecting ADDS a source — it never replaces one —
    /// and each source can be toggled in/out of the unified library independently.
    @Published private(set) var sources: [ConnectedMusicSource] = []

    /// The unified library: every enabled source folded into one, deduped by
    /// recording (`LibraryAggregator`). The runner's own music only — nothing is
    /// substituted when it's empty.
    @Published private(set) var library: [Track] = []
    /// Track id → recording id over EVERY connected source (enabled or not), so what
    /// the app learns through one copy of a song applies to its duplicates in other
    /// apps — and survives sources being toggled in and out.
    @Published private(set) var recordingAliases = RecordingAliases()
    /// Set when tempo couldn't be sourced (Spotify restricted, or no BPM tags) —
    /// shown to the user so an empty/thin library is explained, not silent.
    @Published private(set) var bpmNote: String?

    @Published private(set) var session: SessionController?

    /// Presents the run history (Library) as a sheet over the current screen.
    @Published var showingLibrary = false

    /// A run requested from somewhere other than the Go tab — today, the Sound tab's
    /// tempo ladder. Carries the pace that row stands for and the tracks it holds, so
    /// starting a run from an intensity actually runs at that intensity, on that music.
    ///
    /// `MainTabView` watches this to switch tabs; `SessionSetupView` consumes it and
    /// clears it, so a request applies once rather than re-arming every time the tab is
    /// revisited.
    struct RunRequest: Equatable {
        let sourceName: String
        let targetPaceSecPerKm: Double
        let tracks: [Track]

        static func == (a: RunRequest, b: RunRequest) -> Bool {
            a.sourceName == b.sourceName
                && a.targetPaceSecPerKm == b.targetPaceSecPerKm
                && a.tracks.map(\.id) == b.tracks.map(\.id)
        }
    }

    @Published var runRequest: RunRequest?

    /// Ask the Go tab to open prefilled for this playlist.
    func requestRun(from playlist: Playlist) {
        guard let pace = playlist.suggestedPaceSecPerKm else { return }
        runRequest = RunRequest(sourceName: playlist.name,
                                targetPaceSecPerKm: pace,
                                tracks: playlist.tracks)
    }

    /// Routes per-track calls (play / ISRC / analyzable URL) to whichever connected
    /// service owns the track. Nil until a source is connected and enabled.
    private var router: MusicSourceRouter?
    private let repository = SessionRepository()

    /// The provider face the live session talks to — one object regardless of how
    /// many services are connected beneath it.
    var musicProvider: MusicProviderProtocol? { router }

    /// Connect a service (or refresh one that's already connected) and fold its
    /// library into the unified pool. Other connected sources are untouched.
    func connect(_ choice: ProviderChoice) async -> Bool {
        let provider = sources.first(where: { $0.choice == choice })?.provider
            ?? makeProvider(for: choice)
        return await connect(choice, using: provider)
    }

    /// The body of `connect`, taking the provider so a launch-time restore can reuse
    /// the instance it already asked about rather than building a second one.
    private func connect(_ choice: ProviderChoice,
                         using provider: MusicProviderProtocol) async -> Bool {
        guard await provider.requestAuthorization() else { return false }

        // A failed fetch is reported, not swallowed. Silently substituting an empty
        // library is how a broken connection came to look like an empty account.
        var fetchError: String?
        var tracks: [Track] = []
        do {
            tracks = try await provider.fetchLibraryTracks()
        } catch {
            fetchError = "Couldn't read your \(choice.rawValue) library: "
                + error.localizedDescription
        }

        // Surface why tempo may be missing, per provider.
        var note: String? = fetchError
        if fetchError != nil {
            // Keep the failure as the note; a tempo caveat is beside the point when the
            // library didn't load at all.
        } else if let spotify = provider as? SpotifyProvider {
            // The plan matters more than the tempo caveat: a free account's songs can be
            // read and paced against, but Spotify won't let any app start playback, so
            // saying so here beats letting the runner discover it by tapping a song and
            // hearing nothing.
            var parts: [String] = []
            if await spotify.accountIsPremium() == false {
                parts.append("Spotify only lets apps start playback for Premium accounts, "
                    + "so Dromo can read this library but can't play it. Connect Apple "
                    + "Music to hear your runs.")
            }
            if await spotify.bpmUnavailable() {
                parts.append("Spotify doesn't share track tempo with new apps, so Dromo is "
                    + "working out the tempo of your songs itself.")
            }
            note = parts.isEmpty ? nil : parts.joined(separator: " ")
        } else if let apple = provider as? AppleMusicProvider {
            if apple.lastLibraryWasEmpty {
                note = "No Apple Music library is available here (expected in the Simulator)."
            } else if apple.lastLibraryHadNoBPM {
                note = "None of your Apple Music tracks carry a BPM tag yet — on-device "
                    + "tempo analysis (a later build) will supply BPM for tracks you own."
            }
        }

        let source = ConnectedMusicSource(choice: choice, provider: provider,
                                          tracks: tracks, note: note,
                                          isEnabled: storedEnabled(choice))
        if let index = sources.firstIndex(where: { $0.choice == choice }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
        rememberConnected(choice)
        rebuildLibrary()
        // Note: connect() no longer drives navigation — sign-in owns entry to the
        // tabs. It's called from the post-sign-in popup and the You-tab integrations
        // page, both of which are already on `.setup`.
        return true
    }

    /// Toggle a connected source in or out of the unified library. The connection
    /// (auth, tokens) is retained either way; the choice persists across launches.
    func setSource(_ choice: ProviderChoice, enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.choice == choice }) else { return }
        sources[index].isEnabled = enabled
        storeEnabled(choice, enabled)
        rebuildLibrary()
    }

    /// Fully remove a service: its tracks leave the pool and reconnecting re-auths.
    ///
    /// Also clears the remembered toggle. Otherwise a runner who switched a service
    /// off and then removed it would reconnect later and find it connected but still
    /// out of the mix, with nothing on screen explaining why.
    func disconnect(_ choice: ProviderChoice) {
        // Drop the stored credential too, not just the in-memory source. Now that
        // authorizations survive relaunching, forgetting only the source would leave a
        // usable Spotify token in the Keychain after the runner asked to remove the
        // service — and the next connect would silently reuse it, so "Remove" would
        // not have removed anything.
        if let spotify = sources.first(where: { $0.choice == choice })?.provider
            as? SpotifyProvider {
            spotify.auth.signOut()
        }
        sources.removeAll { $0.choice == choice }
        forgetConnected(choice)
        storeEnabled(choice, true)
        rebuildLibrary()
    }

    /// Recompute the unified library, note, and router from the enabled sources.
    private func rebuildLibrary() {
        let enabled = sources.filter(\.isEnabled)
        let merged = LibraryAggregator.merged(enabled.map(\.tracks))
        let notes = enabled.compactMap(\.note)

        // The library is the runner's own music and nothing else. There was a fallback
        // here that substituted a demo catalog whenever a connected source yielded
        // nothing, which meant a failing integration presented as a working one stocked
        // with songs the runner doesn't own — the failure was invisible and the music
        // was a stranger's. An empty library is now allowed to be empty, and the UI
        // says so. Dromo's own mixes remain a separate, labelled source (CatalogLibrary),
        // not something silently poured into "your music".
        library = merged
        bpmNote = notes.isEmpty ? nil : notes.joined(separator: " ")
        // Aliases span ALL sources, not just enabled ones: learning attached to a
        // recording must survive the copy that taught it being toggled out.
        recordingAliases = RecordingAliases(libraries: sources.map(\.tracks))
        RecordingAliasesHolder.current = recordingAliases
        router = enabled.isEmpty ? nil : MusicSourceRouter(sources: enabled.map {
            (kind: $0.choice.trackProvider, provider: $0.provider, tracks: $0.tracks)
        })

        // Restarting enrichment cancels whatever lookup is in flight, so don't do it
        // for a rebuild that didn't change the library — toggling a source whose songs
        // are all duplicates of another's, say. The ledger makes a restart cheap rather
        // than wasteful (attempted tracks are already recorded and get skipped), but an
        // in-flight request dropped for nothing is still worth avoiding.
        // Tempo already worked out on a previous launch is applied before anything is
        // looked up again. Providers hand back the same untagged library every time, so
        // without this the cache — which is durable, and which the run pool has always
        // read — was invisible to everything the runner browses, and each launch looked
        // like the tempo profile was being built from scratch.
        Task { await applyCachedTempo() }

        let ids = Set(merged.map(\.id))
        guard ids != enrichedLibraryIDs else { return }
        enrichedLibraryIDs = ids
        startEnrichment(for: merged)
    }

    /// Fold cached tempo into the browsable library, keyed by recording so a value
    /// learned through one service's copy of a song serves the others.
    private func applyCachedTempo() async {
        // Expanded through the alias map, the same way the run pool reads it: a tempo
        // cached under a recording reaches whichever service's copy is in the library.
        let enriched = recordingAliases.expanded(await EnrichedBPMStore().all())
        guard !enriched.isEmpty else { return }

        var changed = false
        let updated = library.map { track -> Track in
            guard track.bpm <= 0, let bpm = enriched[track.id], bpm > 0 else { return track }
            changed = true
            return Track(id: track.id, title: track.title, artist: track.artist,
                         bpm: bpm, energyLevel: track.energyLevel,
                         durationSeconds: track.durationSeconds, provider: track.provider)
        }
        guard changed else { return }
        library = updated
    }

    /// The library the current enrichment pass was started for.
    private var enrichedLibraryIDs: Set<String> = []

    // MARK: - Source toggle persistence

    private static let disabledSourcesKey = "music.sources.disabled"

    private func storedEnabled(_ choice: ProviderChoice) -> Bool {
        let disabled = UserDefaults.standard.stringArray(forKey: Self.disabledSourcesKey) ?? []
        return !disabled.contains(choice.rawValue)
    }

    private func storeEnabled(_ choice: ProviderChoice, _ enabled: Bool) {
        var disabled = Set(UserDefaults.standard.stringArray(forKey: Self.disabledSourcesKey) ?? [])
        if enabled { disabled.remove(choice.rawValue) } else { disabled.insert(choice.rawValue) }
        UserDefaults.standard.set(Array(disabled).sorted(), forKey: Self.disabledSourcesKey)
    }

    // MARK: - Auth (local mock)

    /// Create an account or sign in, then advance to the tabs. On first sign-in with
    /// no connected source, surface the "Add your music" popup.
    func authenticate(create: Bool, email: String, password: String) -> Result<Void, Error> {
        do {
            if create {
                try account.createAccount(email: email, password: password)
            } else {
                try account.signIn(email: email, password: password)
            }
            withAnimation { screen = .setup }
            if sources.isEmpty { showingMusicSetup = true }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Sign out and reset music/session state, returning to the auth screen.
    func signOut() {
        account.signOut()
        // Revoke the music credentials with the account. Connections now outlive the
        // process, so leaving them would hand the next person to sign in on this device
        // the previous runner's Spotify library.
        for source in sources {
            (source.provider as? SpotifyProvider)?.auth.signOut()
            forgetConnected(source.choice)
        }
        sources = []
        router = nil
        library = []
        enrichedLibraryIDs = []
        recordingAliases = RecordingAliases()
        RecordingAliasesHolder.current = recordingAliases
        bpmNote = nil
        session = nil
        showingMusicSetup = false
        withAnimation { screen = .auth }
    }

    // MARK: - BPM enrichment (GetSongBPM)

    /// Progress of the one-time background BPM lookup for DRM/untagged tracks.
    @Published private(set) var enrichmentProgress: LibraryEnrichmentPass.Progress?
    /// What the last background pass actually achieved — which sources answered, and
    /// what got deferred to the next pass.
    @Published private(set) var lastEnrichmentResult: LibraryEnrichmentPass.Result?
    private var enrichmentTask: Task<Void, Never>?

    /// Walks the enrichment chain for tracks with no usable tempo, cheapest and most
    /// trustworthy source first, caching every hit with its provenance. Runs in the
    /// background, resumes across launches, and yields to the network gate — a run is
    /// never blocked on it (ARCHITECTURE §6, Phase 2).
    ///
    /// Order matters and is enforced by `BPMSourceChain`, not by this wiring:
    ///   Global Track Table (ISRC) → the platform's own tag → GetSongBPM → Spotify.
    /// Spotify is last on purpose: audio-features is restricted for new apps and may
    /// disappear (see memory: spotify-bpm-restriction).
    private func startEnrichment(for tracks: [Track]) {
        // Nothing to ask, so don't ask. The pass only ever sees tracks whose tempo is
        // already 0, which means the platform's own tag has failed for them — so with no
        // remote source configured the chain cannot answer for a single track, and
        // running it just burns the ledger's retry budget against a wall. The coverage
        // card says so rather than leaving the runner watching a tally that never moves.
        let available = TempoSources.current()
        guard available.canLookUpTempo else {
            enrichmentProgress = nil
            return
        }

        // Captured before the closure so identity resolution doesn't hop the main actor
        // for every track it checks. The router sends each track's ISRC lookup to the
        // service that owns it, so a mixed library enriches correctly.
        let provider: MusicProviderProtocol? = self.router
        var sources: [BPMSourcing] = []
        if available.hasTrackTable {
            // 1. Someone already measured this recording — one cheap request, best value.
            //    `Track` carries no ISRC, so identity is resolved lazily inside the
            //    source: only for tracks that actually reach a lookup.
            sources.append(
                TrackTableBPMSource(api: HTTPTrackTableClient(baseURL: LibrarySync.baseURL),
                                    cache: GRDBTrackFactsCache(),
                                    resolveIdentity: { id in
                                        await provider?.catalogISRC(forTrackID: id)
                                    }))
        }
        // 2. The tempo the platform handed us for free (MPMediaItem.beatsPerMinute).
        sources.append(ProviderTagSource())
        if !Config.getSongBPMKey.isEmpty {
            sources.append(LegacyBPMSource(source: .getSongBPM,
                                           lookup: GetSongBPMClient(apiKey: Config.getSongBPMKey)))
        }
        if !Config.spotifyClientID.isEmpty, !Config.spotifyClientSecret.isEmpty {
            sources.append(LegacyBPMSource(
                source: .spotify,
                lookup: SpotifyBPMResolver(clientID: Config.spotifyClientID,
                                           clientSecret: Config.spotifyClientSecret)))
        }

        enrichmentTask?.cancel()
        let store = EnrichedBPMStore()
        // Hits are cached once per RECORDING: a BPM looked up through one app's copy
        // serves its duplicates in every other app, with no second request.
        let aliases = recordingAliases
        let pass = LibraryEnrichmentPass(
            chain: BPMSourceChain(sources),
            sink: CollectiveBPMSink(base: store, aliases: aliases),
            ledger: GRDBEnrichmentLedger(),
            gate: EnrichmentGate.shared.isOpen)

        enrichmentTask = Task { [weak self] in
            let cached = await store.all()
            // Only tracks with nothing usable yet. The ledger decides which of those
            // are due — this filter is just "don't ask about what we already know",
            // under the track's own id (legacy cache) or its recording's.
            let items = tracks
                .filter { $0.bpm <= 0 && cached[$0.id] == nil
                    && cached[aliases.recordingID(for: $0.id)] == nil }
                .map { EnrichmentItem(trackID: $0.id, title: $0.title, artist: $0.artist,
                                      providerBPM: $0.bpm) }
            guard !items.isEmpty else { return }
            let result = await pass.run(items) { progress in
                Task { @MainActor in
                    self?.enrichmentProgress = progress
                }
            }
            await MainActor.run {
                self?.enrichmentProgress = nil
                self?.lastEnrichmentResult = result
            }
            // Fold what the pass just resolved into the browsable library, so tempo
            // shows up as it's learned instead of only after the next launch.
            await self?.applyCachedTempo()
        }
    }

    func startSession(targetPaceSecondsPerKm: Double, settings: UserSettings) {
        let router = self.router
        let controller = SessionController(
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            settings: settings,
            tracks: library,
            playback: { track in try? await router?.play(track: track) }
        )
        session = controller
        withAnimation { screen = .session }
        controller.begin()
    }

    func finishSession() {
        session?.end()
        if let completed = session?.completedSession {
            let repository = repository
            Task { try? await repository.save(completed) }   // persist to GRDB
        }
        withAnimation { screen = .summary }
    }

    func startOver() {
        session = nil
        withAnimation { screen = .setup }
    }

    // MARK: - Provider selection

    private func makeProvider(for choice: ProviderChoice) -> MusicProviderProtocol {
        switch choice {
        case .appleMusic:
            return AppleMusicProvider()
        case .spotify:
            // Real Spotify the moment a SPOTIFY_CLIENT_ID exists; mock otherwise.
            return SpotifyConfig.isConfigured ? SpotifyProvider() : MockSpotifyProvider()
        }
    }
}
