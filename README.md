# Dromo

Pace-adaptive music app for runners (iOS 16+, watchOS 9+). See the build
specification for the full product definition and roadmap.

## Repository layout

```
Dromo/
├── project.yml             # XcodeGen project definition (source of truth)
├── Dromo.xcodeproj           # generated — `xcodegen generate` (gitignored)
├── Secrets.example.xcconfig # secrets template (committed)
├── Secrets.xcconfig         # real secrets (gitignored, Section 8)
├── Packages/
│   └── DromoCore/            # Platform-agnostic core engine (Phase 1)
│       ├── Sources/DromoCore/
│       │   ├── Models/     # Session, Track, PaceLog, TrackPlay, UserSettings
│       │   ├── Engine/     # PaceEngine, GapCalculator, BPMAdapter, SessionStateMachine
│       │   └── Music/      # MusicSequencer + protocols + in-memory library
│       └── Tests/DromoCoreTests/
├── Dromo/                    # iOS app target (Section 3 tree) — imports DromoCore
│   ├── App/                # DromoApp, AppDelegate, RootView
│   ├── Core/               # Audio, Music, Location, Health (platform-specific)
│   ├── Data/               # Database, Repositories (DromoCore models are reused)
│   ├── Features/           # Onboarding, Session, PostRun, Library, Settings
│   ├── Shared/             # Components, Extensions, DesignSystem, Config
│   ├── Services/           # Supabase, RevenueCat, Strava, Sentry, PostHog
│   └── Resources/          # Info.plist, Assets.xcassets, Localizable.strings
├── DromoWatch/               # watchOS app target — imports DromoCore
├── DromoTests/               # app unit tests (smoke + linkage)
└── DromoUITests/             # app UI tests (launch smoke)
```

The architecture follows the spec's recommendation: the platform-agnostic,
testable logic lives in the `DromoCore` Swift package, and the iOS/watchOS UI and
external integrations live in a separate Xcode app target that imports it. The
engine, domain models, and sequencer are **not** duplicated in the app target —
they come from `DromoCore`, so the Section 3 `Core/Engine` and `Data/Models`
files live in the package rather than the app.

## Phase 0 — Project scaffold

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonsm/XcodeGen):

```bash
brew install xcodegen      # one-time
cp Secrets.example.xcconfig Secrets.xcconfig   # then fill in real values
xcodegen generate          # regenerate Dromo.xcodeproj after editing project.yml
open Dromo.xcodeproj
```

Targets: `Dromo` (iOS 16), `DromoWatch` (watchOS 9), `DromoTests`, `DromoUITests`.
Local dependency on `DromoCore`; SPM dependencies per Section 2.5 (GRDB,
KeychainAccess, Sentry, PostHog, RevenueCat). Bundle id prefix `com.daed`.
Remaining Section 3 leaf files exist as compiling stubs tagged with the phase
that fills them in.

## Core UX flow (built)

The app boots into the end-to-end loop: **Connect Spotify → set pace or goal
time → live session where the music BPM pushes/eases to match your pace.**

- `App/AppCoordinator` — Connect → Setup → Active → Summary navigation.
- `Features/Onboarding/ConnectMusicView` — links a provider via
  `MusicProviderProtocol` (demo uses `Core/Music/MockSpotifyProvider` + a
  BPM-spanning `MockMusicCatalog`; the real `SpotifyProvider` drops in behind the
  same protocol).
- `Features/Session/SessionSetupView` — target pace directly, or a goal finish
  time for a distance (5K/10K/Half/Marathon) → derived pace; plus BPM sensitivity.
- `Core/Session/SessionController` — the 1 Hz loop wiring DromoCore:
  pace → `PaceEngine` (smoothing) → gap → `BPMAdapter` (ramped target BPM,
  ±2/update) → `MusicSequencer` (closest-BPM track). Drives the HUD's PUSH /
  ON PACE / EASE status.
- `Features/Session/ActiveSessionView` — live HUD. Pace comes from a `PaceSource`
  (`Core/Location/`): **`LocationManager` (real CoreLocation GPS)** on device,
  `SimulatedPaceSource` in the Simulator. The on-screen pace control shows only
  when `session.usesSimulatedPace` is true, so it vanishes on a real device.
- `Features/PostRun/PostRunSummaryView` — stats, a dual-axis **pace vs target-BPM
  chart** (Swift Charts; the two lines rise together as you fall behind), and
  **export to Strava / Apple Health**.

### Export
- `Services/StravaService` — OAuth (browser, `Services/Strava/StravaAuthService`
  + shared `Core/Auth/WebAuthenticator`) then a multipart **GPX upload**
  (`GPXBuilder`). Needs `STRAVA_CLIENT_ID` + `STRAVA_CLIENT_SECRET`.
- `Core/Health/HealthKitManager` — saves an `HKWorkout` + GPS route via
  `HKWorkoutBuilder`/`HKWorkoutRouteBuilder`. Needs the HealthKit capability on
  the App ID (device).
- `SessionController` logs a per-tick `PaceLog` (real GPS coordinates on device;
  dead-reckoned in the Simulator so the GPX/route still have geometry) and builds
  an DromoCore `Session` on completion. Export lives in `Features/PostRun/ExportViewModel`.

## Persistence & history (GRDB)

- `Data/Database/DatabaseManager` opens a `DatabaseQueue` at
  `Application Support/Dromo.sqlite` and runs the **Section 4.2 schema** migration
  (`sessions`, `tracks`, `pace_logs`, `track_plays` + indexes); falls back to an
  in-memory DB if the file can't be opened.
- GRDB records (`Data/Database/*Record.swift`) mirror those tables;
  `Data/Repositories/SessionRepository` maps DromoCore `Session` ⇄ rows and offers
  `save` / `summaries` / `fullSession` / `delete`.
- On finish, `AppCoordinator` persists the completed `Session`.
- `Features/Library/LibraryView` (sheet, reachable via **History** on the Connect
  and Summary screens) lists saved runs with swipe-to-delete;
  `LibraryDetailView` reconstructs the run from the DB and reuses `PaceChartView`.

Verified by `DromoFlowUITests`: after a run it opens History, asserts the saved run
is listed, opens the detail, and confirms the reconstructed chart renders.

## Audio crossfade

`Core/Audio/AudioEngine` + `CrossfadeController` implement an **equal-power
crossfade** between two `AVAudioPlayerNode` decks (`CrossfadeCurve`, unit-tested:
outgoing² + incoming² == 1 across the blend). This works for **Dromo-owned local
audio** (resolved via `CrossfadeController.urlProvider`). Streaming providers
(Spotify / Apple Music) own their playback and can't be sample-crossfaded, so the
controller no-ops for them and the provider's `play(track:)` handles the switch.

Verified on the iOS simulator via `DromoUITests/DromoFlowUITests`: Connect → Setup →
ON PACE on target, then **PUSH** (and BPM ramp + faster track) after slowing down.

## Spotify integration (real)

`Core/Music/Spotify/` implements the real provider behind `MusicProviderProtocol`:

- **Auth** — `SpotifyAuthService`: Authorization Code + PKCE via
  `ASWebAuthenticationSession` (system frameworks only, no binary SDK). Tokens are
  stored in the Keychain (`KeychainAccess`) and refreshed transparently.
- **Library + BPM** — `SpotifyWebAPI`: `/me/tracks` for the library and
  `/audio-features` for tempo.
- **Playback** — Spotify App Remote (`SpotifyAppRemoteController`, gated behind
  `#if canImport(SpotifyiOS)`) when the framework is present; otherwise the Web
  API `/me/player/play` fallback (Premium + active device).

The app **auto-selects** the real `SpotifyProvider` as soon as a
`SPOTIFY_CLIENT_ID` is present (`SpotifyConfig.isConfigured`); with no client ID
it uses the mock catalog so the demo/tests run offline.

### To go live
1. Register an app at developer.spotify.com; add redirect URI `ora://spotify-callback`.
2. Put the client ID in `Secrets.xcconfig` (`SPOTIFY_CLIENT_ID = …`).
3. (Optional, for in-app playback control) download `SpotifyiOS.xcframework`,
   drop it in `Frameworks/`, uncomment the dependency in `project.yml`, and
   `xcodegen generate`.

### ⚠️ BPM data caveat
Spotify **restricted the `/v1/audio-features` (tempo) endpoint** in Nov 2024 for
new apps and apps in development mode. A brand-new Dromo Spotify app likely cannot
read BPM from Spotify — `SpotifyWebAPI` detects the 403 and the setup screen shows
a warning. Because Dromo is BPM-driven, **Apple Music is the BPM-reliable primary
provider** (below); Spotify remains available for auth/library/playback.

## Apple Music integration (primary BPM source)

`Core/Music/AppleMusicProvider` reads the user's library via the **MediaPlayer**
framework and takes BPM from `MPMediaItem.beatsPerMinute` — the mainstream tempo
source still exposed (no binary SDK, no entitlement to compile). Playback uses
`MPMusicPlayerController.applicationMusicPlayer`. The connect screen offers both
Apple Music (primary) and Spotify; `AppCoordinator.connect(_:)` selects the
provider. Tracks without a BPM tag are dropped, and an empty library (e.g. the
Simulator) transparently falls back to demo tracks with a visible note.

Coverage caveat: `beatsPerMinute` is only present when a track's metadata carries
it, so real-library coverage varies; needs a device with a populated library to
fully validate.

## What's implemented (Phase 1 core, Spec §4–5)

| Component | File | Notes |
|---|---|---|
| Domain models | `Models/*.swift` | `Session`, `Track`, `PaceLog`, `TrackPlay`, `UserSettings` — Codable, spec §4.1 |
| Pace engine | `Engine/PaceEngine.swift` | `actor`; 1Hz ingestion, 10-reading rolling window, accuracy/stationary filtering (§5.1) |
| Gap calculator | `Engine/GapCalculator.swift` | `actual − target`; +ve = behind, −ve = ahead |
| BPM adapter | `Engine/BPMAdapter.swift` | gap → BPM offset, sensitivity curves, ±2 BPM/update cap, floor/ceiling clamp (§5.2) |
| Session state machine | `Engine/SessionStateMachine.swift` | idle → setup → countdown → active ⇄ paused → completed (§5.4) |
| Music sequencer | `Music/MusicSequencer.swift` | closest-BPM selection, no-repeat, min play time, tolerance fallback (§5.3) |
| Library / crossfade seams | `Music/BPMLibraryProviding.swift`, `TrackTransitioning.swift` | protocols so the sequencer is testable without AVFoundation/SQLite |
| In-memory library | `Music/InMemoryBPMLibrary.swift` | preview/test impl + base for the cached index |

### Faithfulness note
`MusicSequencer`'s `Date()` calls are routed through an injectable `now` clock
so the minimum-play-duration rule is deterministically testable. Logic is
otherwise identical to the spec.

## Tests (Spec §13.1)

26 unit tests across `GapCalculatorTests`, `BPMAdapterTests`, `PaceEngineTests`,
`MusicSequencerTests`, `SessionStateMachineTests` — all passing.

```bash
cd Packages/DromoCore
swift test
```

## Deferred to the Xcode app target (need device / Xcode / credentials)

These were intentionally **not** built this session because they cannot be
compiled or verified from a macOS command line:

- SwiftUI views (Onboarding, Session, PostRun, Library, Settings) and Live Activity
- `LocationManager` (CoreLocation), `AudioEngine` + `CrossfadeController` (AVFoundation)
- Music providers: MusicKit (`AppleMusicProvider`), Spotify SDK (`SpotifyProvider`)
- Integrations: Strava, HealthKit, Supabase, RevenueCat, Sentry, PostHog
- GRDB-backed `BPMLibrary` / repositories (conform to `BPMLibraryProviding`)
- Apple Watch target + WatchConnectivity

When the Xcode project is created, add `Packages/DromoCore` as a local package
dependency and have the app types implement the `BPMLibraryProviding` and
`TrackTransitioning` protocols.
