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
    }

    /// Every connected service. Connecting ADDS a source — it never replaces one —
    /// and each source can be toggled in/out of the unified library independently.
    @Published private(set) var sources: [ConnectedMusicSource] = []

    /// The unified library: every enabled source folded into one, deduped by
    /// recording (`LibraryAggregator`), with the demo catalog as the fallback when
    /// connected sources yield nothing usable.
    @Published private(set) var library: [Track] = []
    /// Set when tempo couldn't be sourced (Spotify restricted, or no BPM tags) —
    /// shown to the user so an empty/thin library is explained, not silent.
    @Published private(set) var bpmNote: String?

    @Published private(set) var session: SessionController?

    /// Presents the run history (Library) as a sheet over the current screen.
    @Published var showingLibrary = false

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

        guard await provider.requestAuthorization() else { return false }

        let tracks = (try? await provider.fetchLibraryTracks()) ?? []

        // Surface why tempo may be missing, per provider.
        var note: String?
        if let spotify = provider as? SpotifyProvider, await spotify.bpmUnavailable() {
            note = "Spotify doesn't expose track tempo for new apps (its audio-features "
                + "endpoint is restricted)."
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

    /// Fully remove a service (its tracks leave the pool; reconnecting re-auths).
    func disconnect(_ choice: ProviderChoice) {
        sources.removeAll { $0.choice == choice }
        rebuildLibrary()
    }

    /// Recompute the unified library, note, and router from the enabled sources.
    private func rebuildLibrary() {
        let enabled = sources.filter(\.isEnabled)
        var merged = LibraryAggregator.merged(enabled.map(\.tracks))
        var notes = enabled.compactMap(\.note)

        // Keep the app usable when the enabled sources yield no BPM-bearing tracks
        // (Simulator, DRM-only streaming, or an untagged library) — fall back to the
        // built-in catalog. This is the architecture's sanctioned fallback, not an
        // error. With no sources at all the library stays empty: the session pool's
        // own catalog-first path covers the "run before connecting" promise.
        if merged.isEmpty, !enabled.isEmpty {
            merged = MockMusicCatalog.tracks
            notes.append("Using Dromo's built-in demo catalog so you can try the "
                + "full pace → BPM → music loop.")
        }

        library = merged
        bpmNote = notes.isEmpty ? nil : notes.joined(separator: " ")
        router = enabled.isEmpty ? nil : MusicSourceRouter(sources: enabled.map {
            (kind: $0.choice.trackProvider, provider: $0.provider, tracks: $0.tracks)
        })
        startEnrichment(for: merged)
    }

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
        sources = []
        router = nil
        library = []
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
        // Captured before the closure so identity resolution doesn't hop the main actor
        // for every track it checks. The router sends each track's ISRC lookup to the
        // service that owns it, so a mixed library enriches correctly.
        let provider: MusicProviderProtocol? = self.router
        var sources: [BPMSourcing] = [
            // 1. Someone already measured this recording — one cheap request, best value.
            //    `Track` carries no ISRC, so identity is resolved lazily inside the
            //    source: only for tracks that actually reach a lookup.
            TrackTableBPMSource(api: HTTPTrackTableClient(baseURL: LibrarySync.baseURL),
                                cache: GRDBTrackFactsCache(),
                                resolveIdentity: { id in
                                    await provider?.catalogISRC(forTrackID: id)
                                }),
            // 2. The tempo the platform handed us for free (MPMediaItem.beatsPerMinute).
            ProviderTagSource(),
        ]
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
        let pass = LibraryEnrichmentPass(
            chain: BPMSourceChain(sources),
            sink: store,
            ledger: GRDBEnrichmentLedger(),
            gate: EnrichmentGate.shared.isOpen)

        enrichmentTask = Task { [weak self] in
            let cached = await store.all()
            // Only tracks with nothing usable yet. The ledger decides which of those
            // are due — this filter is just "don't ask about what we already know".
            let items = tracks
                .filter { $0.bpm <= 0 && cached[$0.id] == nil }
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
