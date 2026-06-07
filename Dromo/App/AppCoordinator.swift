import SwiftUI
import DromoCore

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

    enum ProviderChoice: String {
        case appleMusic = "Apple Music"
        case spotify = "Spotify"
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

    /// Tracks fetched from the connected provider (or demo tracks as a fallback).
    @Published private(set) var library: [Track] = []
    @Published private(set) var providerName = ""
    /// Set when tempo couldn't be sourced (Spotify restricted, or no BPM tags) —
    /// shown to the user so an empty/thin library is explained, not silent.
    @Published private(set) var bpmNote: String?

    @Published private(set) var session: SessionController?

    /// Presents the run history (Library) as a sheet over the current screen.
    @Published var showingLibrary = false

    private var provider: MusicProviderProtocol?
    private let repository = SessionRepository()

    /// The connected provider — used by the live session to resolve per-track
    /// identity (ISRC) and analyzable URLs against the Global Track Table.
    var musicProvider: MusicProviderProtocol? { provider }

    func connect(_ choice: ProviderChoice) async -> Bool {
        bpmNote = nil
        providerName = choice.rawValue
        let provider = makeProvider(for: choice)
        self.provider = provider

        guard await provider.requestAuthorization() else { return false }

        var tracks = (try? await provider.fetchLibraryTracks()) ?? []

        // Surface why tempo may be missing for each provider.
        if let spotify = provider as? SpotifyProvider, await spotify.bpmUnavailable() {
            bpmNote = "Spotify doesn't expose track tempo for new apps (its audio-features "
                + "endpoint is restricted)."
        } else if let apple = provider as? AppleMusicProvider {
            if apple.lastLibraryWasEmpty {
                bpmNote = "No Apple Music library is available here (expected in the Simulator)."
            } else if apple.lastLibraryHadNoBPM {
                bpmNote = "None of your Apple Music tracks carry a BPM tag yet — on-device "
                    + "tempo analysis (a later build) will supply BPM for tracks you own."
            }
        }

        // Keep the app usable when no analyzable, BPM-bearing tracks are available
        // (Simulator, DRM-only streaming, or an untagged library) — fall back to the
        // built-in catalog. This is the architecture's sanctioned fallback, not an error.
        if tracks.isEmpty {
            tracks = MockMusicCatalog.tracks
            let prefix = bpmNote.map { $0 + " " } ?? ""
            bpmNote = prefix + "Using Dromo's built-in demo catalog so you can try the "
                + "full pace → BPM → music loop."
        }

        library = tracks
        startEnrichment(for: tracks)
        // Note: connect() no longer drives navigation — sign-in owns entry to the
        // tabs. It's called from the post-sign-in popup and the You-tab integrations
        // page, both of which are already on `.setup`.
        return true
    }

    // MARK: - Auth (local mock)

    /// Create an account or sign in, then advance to the tabs. On first sign-in with
    /// no connected provider, surface the "Add your music" popup.
    func authenticate(create: Bool, email: String, password: String) -> Result<Void, Error> {
        do {
            if create {
                try account.createAccount(email: email, password: password)
            } else {
                try account.signIn(email: email, password: password)
            }
            withAnimation { screen = .setup }
            if provider == nil { showingMusicSetup = true }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Sign out and reset music/session state, returning to the auth screen.
    func signOut() {
        account.signOut()
        provider = nil
        library = []
        providerName = ""
        bpmNote = nil
        session = nil
        showingMusicSetup = false
        withAnimation { screen = .auth }
    }

    // MARK: - BPM enrichment (GetSongBPM)

    /// Progress of the one-time background BPM lookup for DRM/untagged tracks.
    @Published private(set) var enrichmentProgress: BPMEnricher.Progress?
    private var enrichmentTask: Task<Void, Never>?

    /// Looks up BPM (by metadata) for tracks that have none, caching results so the
    /// library becomes tempo-matchable. Runs once in the background; never blocks runs.
    private func startEnrichment(for tracks: [Track]) {
        // BPM sources, in priority order: Spotify Audio Features (best coverage) →
        // GetSongBPM (fallback). Both are background metadata lookups — no user login.
        var lookups: [BPMLookup] = []
        if !Config.spotifyClientID.isEmpty, !Config.spotifyClientSecret.isEmpty {
            lookups.append(SpotifyBPMResolver(clientID: Config.spotifyClientID,
                                              clientSecret: Config.spotifyClientSecret))
        }
        if !Config.getSongBPMKey.isEmpty {
            lookups.append(GetSongBPMClient(apiKey: Config.getSongBPMKey))
        }
        guard !lookups.isEmpty else { return }   // no BPM source configured → skip silently

        enrichmentTask?.cancel()
        let store = EnrichedBPMStore()
        let enricher = BPMEnricher(lookup: ChainedBPMLookup(lookups), sink: store)
        enrichmentTask = Task { [weak self] in
            let cached = await store.all()
            let items = tracks
                .filter { $0.bpm <= 0 && cached[$0.id] == nil }   // only the unknown, uncached
                .map { EnrichmentItem(trackID: $0.id, title: $0.title, artist: $0.artist) }
            guard !items.isEmpty else { return }
            await enricher.enrich(items) { progress in
                Task { @MainActor in self?.enrichmentProgress = progress }
            }
            await MainActor.run { self?.enrichmentProgress = nil }
        }
    }

    func startSession(targetPaceSecondsPerKm: Double, settings: UserSettings) {
        let provider = self.provider
        let controller = SessionController(
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            settings: settings,
            tracks: library,
            playback: { track in try? await provider?.play(track: track) }
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
