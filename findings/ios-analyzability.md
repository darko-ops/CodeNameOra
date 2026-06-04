# Findings — iOS Audio-Analyzability Boundary (Phase 0, Task 0.1)

> **Question this answers:** On a current iOS version, for which audio sources can a third-party
> app obtain **decoded PCM samples** (the prerequisite for on-device BPM/feature analysis)?
>
> **Status legend:**
> - ✅ **Verified by API contract** — long-standing, documented platform behavior; the harness
>   (`Spikes/AnalyzabilityProbe.swift`) confirms it but the conclusion is not in doubt.
> - ⚠️ **Confirm on device** — must be re-run on current hardware/OS via the harness; result is
>   expected but environment-dependent. (This environment has no iOS device, so these are pending.)

## Source → PCM-access table

| # | Source | Decoded PCM obtainable? | API path | Confidence | Notes |
|---|--------|:---:|----------|:---:|-------|
| 1 | Files **imported into the app** (Files app, share sheet, AirDrop, iTunes File Sharing, drag-drop) | **YES** | `AVAudioFile` / `AVAssetReader` over the local URL | ✅ | Full decoded samples, any container the OS decodes (mp3/aac/wav/flac/alac). No DRM. This is the always-works path. |
| 2 | **DRM-free files in the on-device Music library** (CD rips, sideloaded, sync'd local files) | **YES** (when `assetURL != nil`) | `MPMediaItem.assetURL` → `AVAssetReader` | ⚠️ | A non-nil `assetURL` is the signal the asset is locally readable. |
| 3 | **iTunes Store purchases** (iTunes Plus — all purchases since 2009) | **YES** | `MPMediaItem.assetURL` → `AVAssetReader` | ⚠️ | DRM-free AAC; `assetURL` is populated; analyzable. |
| 4 | **Apple Music tracks _added_ to library** (cloud, not downloaded) | **NO** | `assetURL` is `nil` | ✅ | No local asset exists to read. |
| 5 | **Apple Music _downloaded_ tracks** | **NO** | `assetURL` nil, or `AVAssetReader` fails on the protected asset | ⚠️ | FairPlay-protected. `ApplicationMusicPlayer` can play them, but no decoded-sample access is exposed to third parties. |
| 6 | **Apple Music via MusicKit** (`ApplicationMusicPlayer`) | **NO** | Playback API only | ✅ | No sample tap / no render-callback access to the protected stream. |
| 7 | **Streamed Apple Music / Spotify** | **NO** | DRM, no local asset | ✅ | Nothing on disk; no tap. |
| 8 | **Spotify (any state)** | **NO** | iOS SDK is remote-control only | ✅ | No audio samples. Also no BPM: the audio-features endpoint is restricted for new apps (see `[[spotify-bpm-restriction]]`). |

### The single load-bearing signal
`MPMediaItem.assetURL`:
- **non-nil** ⇒ a locally readable asset exists ⇒ feed to `AVAssetReader` ⇒ PCM ⇒ analyzable.
- **nil** ⇒ cloud/DRM item ⇒ **not** analyzable. Do not attempt to defeat this (per ARCHITECTURE §4/§9).

The harness enumerates the library and reports the `assetURL`-nil ratio — that ratio *is* the
analyzable fraction of that library.

## Realistically analyzable fraction of a typical mainstream library

| User profile | Analyzable on their own device | Implication |
|--------------|:---:|-------------|
| Apple Music subscriber, streaming-first library | **~0%** | Their own device can analyze almost nothing. |
| Owns purchases / CD rips / local files | **High (most tracks)** | These users can analyze and **contribute** facts. |

### Why the product still works despite this (the key strategic finding)
This is exactly why ARCHITECTURE's **identity-by-ISRC + Global Track Table** design is load-bearing:

- The **analyzable minority** (owners of DRM-free copies) analyze a recording **once** and publish its
  facts to the Global Track Table, keyed by **ISRC** (the recording's identity, not the file's).
- The **streaming majority** then get those same facts via an **ISRC lookup** — never analyzing,
  never needing decoded samples. A streamed Apple Music track and a CD rip of the same recording
  share an ISRC, so the streamer inherits the owner's measured BPM.
- Where ISRC coverage is thin: (a) any platform-exposed BPM, (b) a 3rd-party BPM API, (c) the
  **fallback catalog** (Phase 6), which arrives pre-tagged.

**Conclusion:** Direct on-device analyzability is low for the mainstream user, but this does **not**
cap the product — it caps how many users are *contributors* vs. *consumers* of the shared table.
The architecture already routes around the DRM wall via ISRC. Onboarding UX should therefore lead
with "your library, made responsive" backed by lookup, and treat local analysis as the contributor
path + long-tail filler, with the fallback catalog guaranteeing day-one magic.

## How to confirm on device (run the harness)
1. Add `Spikes/AnalyzabilityProbe.swift` to a throwaway single-view iOS app target (NOT the Dromo app).
2. Put a known audio file in the app bundle/Documents for source #1.
3. On a device signed into Apple Music with a mixed library, run `AnalyzabilityProbe.run()`.
4. It prints a markdown table: source → `assetURL` present? → `AVAssetReader` succeeded? → error.
5. Paste the device output into this file under "Device run results" below and flip ⚠️ rows to ✅/❌.

### Device run results
_PENDING — no iOS device available in the authoring environment. Fill from a real run._
