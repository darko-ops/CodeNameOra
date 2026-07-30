# Handoff: Dromo app — design language v2 (aligned to the new dromo.fit)

## Overview
Dromo is a pace-adaptive running music app (iOS 16+, watchOS 9+). It reads your running
cadence, plays songs from *your own* library whose BPM matches your stride, and nudges
the tempo up/down to keep you on your target pace.

The **website was rebuilt** on a new visual system: near-black greyscale surfaces, a
single subtle steel accent, a new **wave mark** logo with a plain `DROMO` wordmark, and
a neutral grotesque typeface. **The app has not caught up.** This package is the design
work that brings the app onto the same system.

**Scope of this handoff:** restyle only. No screen is added, removed, or re-flowed —
every design here maps onto a SwiftUI view that already exists in the repo. Treat it as
"retheme these views", not "rebuild these features".

## About the design files
`Dromo Landing Directions.dc.html` is a **design reference created in HTML** — a
prototype showing intended look, not production code to ship. Recreate it in SwiftUI
using the app's existing view structure and design-token files.

Open it and use the canvas ids:
- **`7a`** — the design language sheet (the system itself: surfaces, coaching colour, type, carried-over rules)
- **`7b`** — the live running HUD, two states
- **`8a`** — six more screens: session setup, post-run summary, You/Momentum, You/Sessions, Music, learned data

`logo-wave.png` is the wave mark, copied from the live site (`website/logo-wave.png`,
360×209, ratio 1.72:1, black artwork on transparent — designed to be used as a **mask**
so it takes its colour from the parent).

## Fidelity
**High-fidelity.** Colors, type weights, spacing, and radii below are final. Where a
value replaces an existing token, the old value is given so you can find every call site.

---

## 1. THE SYSTEM (design ref `7a`)

### 1.1 Surfaces — replace the blue-tinted app greys
`Dromo/Shared/DesignSystem/Colors.swift`

| Token | New | Was | Notes |
| --- | --- | --- | --- |
| `oraBackground` | `#0E1013` | `#080A0E` | matches the site's `--bg` |
| `oraSurface` | `#16181C` | `#111318` | cards, list rows, nav bars |
| `oraSurfaceElevated` | `#1F2227` | `#1A1F2E` | the old value was blue-tinted; this is neutral |
| *(new)* `oraBorder` | `rgba(255,255,255,0.07)` | — | hairline borders — the site uses borders, the app used bare fills |
| *(new)* `oraBorderStrong` | `rgba(255,255,255,0.16)` | — | 2px leading/top accent rule on cards |
| `oraTextPrimary` | `#E7E9EC` | `.white` | softened off-white, per the site |
| `oraTextSecondary` | `#9298A1` | `#999999` | |
| `oraTextMuted` | `#5B616A` | `#555555` | |

### 1.2 Coaching colour — the one place the app keeps hue
The neon zone palette is retired. **Rationale:** the HUD tints the whole screen to your
coaching state, so hue is doing real work at a glance mid-run — going fully greyscale
would cost legibility. Instead each state becomes a **hue rotation of the site's steel
accent at matched lightness and chroma**, so the app reads as restrained as the site
while staying instantly distinguishable.

| Token | New | Was | Meaning |
| --- | --- | --- | --- |
| `zoneWarmUp` | `#8FA9C4` | `#4FC3F7` | warm-up · "EASE" / too-fast nudge |
| `zoneSteady` | `#6EA8C9` | `#22D3EE` | steady · "ON PACE" · **the site's accent**, and the app's primary |
| `zonePeak` | `#C98A6E` | `#FF7043` | peak · "SPEED UP" / too-slow nudge |
| `zoneRecovery` | `#A78FC4` | `#CE93D8` | recovery |
| `oraSuccess` | `#7FB09A` | `#4CAF50` | |
| `oraWarning` | `#C9A96E` | `#FF9800` | off-beat feedback, paused/blocked reasons |
| `oraDestructive` | `#C96E6E` | `#F44336` | End run, Sign Out, Reset learned data |

**Two rules that fall out of this, and should be enforced in review:**
1. **The accent marks live or derived values only** — current pace, target pace derived
   from a goal, matched BPM, avg pace, play counts, coverage fill. Static or historical
   numbers stay `oraTextPrimary`.
2. **Semantic colours share the muted chroma.** No saturated red/green/orange anywhere.

**Exception — brand colours are not ours to mute.** Spotify green `#1DB954` in
`MusicProviderButtons` stays exactly as it is.

### 1.3 Typography — drop Syne + DM Mono
`Dromo/Shared/DesignSystem/Typography.swift` currently declares `Syne-ExtraBold`,
`Syne-Bold`, `Syne-SemiBold`, `DMSans-Regular`, `DMMono-Regular`, `DMMono-Medium`.
Per the file's own note these are **not embedded** and already fall back to the system
font — so this change mostly deletes dead intent.

The site uses `"Helvetica Neue", Helvetica, Arial, sans-serif`. On iOS the honest
equivalent is the **system font (SF Pro), `.default` design — not `.rounded`**. Remove
every `design: .rounded` in the session/summary/dashboard views; that softness is what
made the app read as a different product from the site.

| Role | Spec |
| --- | --- |
| Numeric display | `.system(size: 26–30, weight: .bold)`, `monospacedDigit()`, tracking ≈ −0.03em |
| Title | `.system(size: 20–22, weight: .semibold)` |
| Card heading | `.system(size: 15–16, weight: .semibold)` |
| Body | `.system(size: 13–16, weight: .regular)`, `oraTextSecondary` |
| Label / eyebrow | `.system(size: 10–11, weight: .semibold)`, **uppercase, tracking +0.16em**, `oraTextMuted` |

Weights drop overall: the app's `.black`/`.bold` become `.bold`/`.semibold`. Keep
`monospacedDigit()` everywhere it already appears — the site's tabular numerals are
part of the look.

### 1.4 Carried over from the site
- **Wave mark + plain wordmark.** `logo-wave.png` rendered as a template/mask image so
  it inherits `foregroundColor`; `DROMO` at `.semibold`/`.bold`, tracking **+0.04em**,
  mark-to-text gap `0.5em`, mark width `1.72em` against `1em` of text height. **There is
  no Ø** — any earlier DRØMO slash lockup is retired.
- **Light primary buttons.** Primary CTAs become `#E7E9EC` fill with `#16181C` text,
  replacing accent-filled buttons (`Start run`, `New run`, `Pause`, provider refresh).
  Disabled: `oraSurfaceElevated` fill, `oraTextMuted` text. Radius 12–14.
- **Left accent rule on cards.** `oraSurface` fill + hairline border + a 2px
  `oraBorderStrong` leading edge, radius 12–16 — the site's mobile step pattern. Use on
  secondary//settings cards; plain hairline cards elsewhere.
- **Reveal out of blur.** The site's unlock reveal (`opacity 0→1`, `blur(12px)→0`,
  `scale(1.03)→1`, ~1.1s ease) becomes the app's launch transition.

### 1.5 Spacing / shape
`Spacing.swift` is unchanged (`xs 4 / sm 8 / md 16 / lg 24 / xl 32 / xxl 48 / screen 28`).
Radii: cards 16, small cards/buttons 12–14, pills/toggles/meters capsule, nudge badge 18,
album art tile 10.

---

## 2. LIVE RUNNING HUD (design ref `7b`)
Views: `Dromo/Features/Session/LiveHUDView.swift`, `ActiveSessionView.swift`
Driven by: `LiveSessionViewModel` / `LoopState` (unchanged)

Structure is unchanged, top→bottom:
1. **Top row** — the wave mark + `DROMO` in `oraTextSecondary` at ~14pt (new; replaces a
   bare elapsed label), and `End` top-right in `oraTextSecondary` `.semibold`.
2. **Nudge badge** — full width, radius 18, fill `nudgeColor.opacity(0.12)`, label
   centered in `nudgeColor` at ~30pt `.bold` (down from 34 `.black`), tracking +0.02em.
   `hold → "ON PACE"` · `speedUp → "SPEED UP"` · `slowDown → "EASE"`. Subtitle below in
   `oraTextSecondary` ~13pt with the live gap description.
3. **Pace block** — three metrics with hairline dividers: PACE /KM (tinted `nudgeColor`),
   TARGET, TIME. Values ~29pt `.bold` `monospacedDigit()`; labels 10pt `.semibold`
   uppercase +0.16em `oraTextMuted`.
4. **Cadence** — centered `CADENCE` label + `168 spm` (~17pt `.semibold`).
5. **Target-BPM bar** — label row `TARGET BPM` + value in `nudgeColor`. Track
   `oraSurfaceElevated`, height 10, capsule; fill is a gradient from `zoneWarmUp` to the
   current zone colour, width = target position within `minBPM…maxBPM`; a 3px
   `oraTextPrimary` tick marks live cadence; min/max ticks below in `oraTextMuted`.
   When behind pace the label gains `↑` and the gradient trends to `zonePeak`.
6. **Now-playing card** — `oraSurface` + hairline border, radius 16: 52pt art tile
   (`oraSurfaceElevated`, radius 10, music-note glyph fallback), title 16 `.semibold`
   1-line ellipsis, artist 13 `oraTextSecondary`, right-aligned BPM 20 `.bold` in
   `nudgeColor` over a 9pt `BPM` label (+0.14em). Empty title → "Finding your tempo…".
7. **Feedback controls** — 3 icon+label buttons: `Like` (`zoneSteady`), `Off-beat`
   (`oraWarning`), `Skip` (`oraTextSecondary`). Disabled at 0.4 opacity with no track.
8. **Pause / End** — `Pause` is now a **light** button (`#E7E9EC` / `#16181C`), radius 12;
   `End` is `oraSurfaceElevated` fill with `oraDestructive` text.

**Pace-deviation alert** (state 2 in `7b`): while outside the ±20 s/km band, a radial
glow fills the screen in the direction's tint (too-slow `zonePeak`, too-fast
`zoneWarmUp`) at ~0.32 alpha at center, plus a centered block: icon (hare / tortoise),
~37pt `.bold` title (`TOO SLOW` / `TOO FAST`), and a `.semibold` subtitle
(`Pick up the pace` / `Ease off`) in a light tint of the zone colour. Non-interactive
(`allowsHitTesting(false)`), opacity transition, unchanged 30s repeating beep.

Animations unchanged: nudge badge `easeInOut 0.3`, track swap `easeInOut 0.4`, alert
overlay `easeInOut 0.4`.

---

## 3. THE OTHER SCREENS (design ref `8a`)

### 3.1 Session setup — `Features/Session/SessionSetupView.swift`
- Header `Set your target` 22pt `.semibold`; the km/mi `Picker` becomes a greyscale
  segmented control: track `oraSurface` + hairline, selected segment `oraSurfaceElevated`,
  unselected text `oraTextMuted`. **Apply this segmented treatment app-wide** (mode
  picker, sensitivity, race distance, You tabs).
- **Target card** — `oraSurface`, radius 16. Wheel pickers: selected row
  `rgba(255,255,255,0.05)` highlight, selected value 22pt `.semibold` tabular, neighbours
  `oraTextMuted`; unit suffixes (`MIN`/`SEC`, `/km`) 10pt `.semibold` +0.14em muted.
  Divider hairline, then `Target pace` label + the derived value at 22pt `.bold` tabular
  in `zoneSteady` (**derived → accent**, rule 1).
- **Distance goal (optional)** — left-accent-rule card. Value `10.0 km` 20pt `.bold`
  tabular in `zoneSteady` when set, `oraTextMuted` when `Off`. `Stepper` restyled as a
  two-segment `oraSurfaceElevated` −/+ control. Explainer 12pt `oraTextSecondary`
  (existing copy verbatim).
- **BPM sensitivity** — left-accent-rule card, greyscale segmented Easy/Standard/
  Aggressive, `vm.sensitivityDescription` below.
- **`Start run`** — light button, radius 14. Invalid → `oraSurfaceElevated` /
  `oraTextMuted`.
- The `bpmWarning` banner keeps its shape; icon + text move to `oraWarning` `#C9A96E`
  over `oraWarning.opacity(0.12)`.

### 3.2 Post-run summary — `Features/PostRun/PostRunSummaryView.swift`
- Header `Run complete` 26pt `.semibold` + `Nice work.` secondary.
- **Stats grid** 2-up, `oraSurface` + hairline, radius 14. Values 22pt `.bold` tabular,
  labels 11pt `oraTextMuted`. All six read `oraTextPrimary` **except `Avg pace`**, which
  is `zoneSteady` (derived). Keep `minimumScaleFactor(0.6)` / `lineLimit(1)`.
- **`PACE vs BPM` card** wrapping `PaceChartView` (`Features/PostRun/PaceChartView.swift`).
  Only the style scale changes: `chartForegroundStyleScale(["Pace": .zoneSteady,
  "BPM": .zonePeak])` now resolves to `#6EA8C9` / `#C98A6E`. Leading axis pace labels
  tint `zoneSteady`, trailing BPM labels `zonePeak`, grid lines `oraSurfaceElevated`,
  dashed target `RuleMark` + `target` annotation `oraTextMuted`, x-axis clock labels
  muted, legend bottom. Normalisation, downsampling, and `.monotone` interpolation are
  untouched.
- **`WHAT MOVED YOU`** — `Features/PostRun/WhatMovedYouCard.swift`. Row arrows: helped
  `zoneSteady`, drag row `zonePeak`, split by a hairline divider. Keep the measured-only
  copy (`"your cadence came up 6 spm while this played"`) and keep hiding the card
  entirely when there's nothing to attribute.
- **`EXPORT`** — rows unchanged; status glyph colours follow the new semantic tokens
  (`done → oraSuccess #7FB09A`, `failed → oraDestructive #C96E6E`).
- **`New run`** becomes a light button; `View history` stays a quiet secondary label.

### 3.3 You — `Features/Library/LibraryView.swift` (+ `DashboardView.swift`)
Nav bar `oraSurface` with hairline bottom; title `You`; leading toolbar glyphs
(`music.note` → Music, `brain` → learned data) move from `zoneSteady` to
`oraTextSecondary` — they're navigation, not live data. Greyscale segmented
Momentum / Sessions / Goals.

- **Momentum tab** = `DashboardView` only. The three tiles
  (`MOMENTUM` / `TOTAL` / `LISTENS`) **lose their per-tile hues** — the real code tints
  them `zonePeak` / `zoneSteady` / `zoneWarmUp`, which implies a distinction that doesn't
  exist. Values become `oraTextPrimary` 30pt `.bold` tabular; the tiles are told apart by
  their labels. Then `MOST PLAYED`: `oraSurface` card, rank in `oraTextMuted`, title/
  artist, play count `32×` in `zoneSteady` (derived), hairline separators.
- **Sessions tab** = the `List` of `SummaryRow`s: `.plain` style, row background
  `oraSurface`, separator tint `oraSurfaceElevated`, date 15pt `.semibold`,
  `8.42 km · 46:19` 12pt secondary, avg pace right-aligned 15pt `.bold` tabular
  `zoneSteady` over a 10pt `avg pace` muted label. Swipe-to-delete unchanged. Empty
  state copy unchanged.

### 3.4 Music — `Features/Settings/MusicIntegrationsView.swift`
- Nav `Music`, inline title, `oraSurface` bar.
- **`Your sources` card** — one row per connected source: state glyph
  (`checkmark.circle.fill` in `zoneSteady` when enabled, `circle` in `oraTextMuted` when
  not), name 16 `.semibold`, subtitle either `"N tracks in the mix"` or
  `"Out of the mix — connection kept"`, a `zoneSteady`-tinted `Toggle`, and a quiet
  `trash` button in `oraTextMuted`. **Preserve the toggle-vs-remove distinction** — the
  toggle is the everyday control; remove costs a re-authorization and stays visibly
  quieter.
- **`Dromo Mixes` row** — `waveform` glyph, **not a toggle**. Honour
  `CatalogLibrary.shared.isStocked`: unstocked → name `oraTextSecondary`, subtitle
  `"Not in this build yet — your connected libraries carry every run"`. Do not present
  coverage this build can't play.
- Explainer paragraph, then **`MusicProviderButtons`**: Apple Music button becomes the
  light button (`#E7E9EC` / `#16181C`) — it was already white, so this is now literally
  the same token as every other primary CTA. **Spotify keeps `#1DB954` on black.** Labels
  stay dynamic (`Continue with X` / `Refresh X library` / `Connecting…`).
- **`TEMPO COVERAGE` card** — `Features/Settings/LibraryCoverageCard.swift`. Big
  `\(tagged)` 28pt `.bold` tabular `oraTextPrimary` + `of \(total) tracks` secondary;
  capsule meter on `oraSurfaceElevated`, fill `zoneSteady` when
  `coverage.carriesSession()` else `zoneWarmUp`, `easeInOut 0.4` on change;
  `coverage.summary` below; `pausedReason` in `oraWarning`; `Use cellular data` toggle
  tinted `zoneSteady`. Note the meter fills toward "your library carries the run", not
  toward 100%.
- **`Signed in as`** + email + `Sign Out` — `oraSurface` fill, `oraDestructive` text.
- The remove `confirmationDialog` copy is unchanged.

### 3.5 What Dromo has learned — `Features/Settings/LearnedDataView.swift`
- Title 20pt `.semibold` + the existing three-sentence privacy explainer verbatim.
- **Counts card** — one row per `PaceMode` using the real labels
  (`Tracks measured while behind pace` / `on pace` / `while ahead`) plus
  `Tracks you rated`. Labels 13pt `oraTextSecondary`; counts 15pt `.semibold` tabular
  `oraTextPrimary` (**not** accent — these are historical totals, rule 1).
- **`Reset what Dromo has learned`** — `oraDestructive.opacity(0.2)` fill,
  `oraDestructive` text, radius 12. Confirmation dialog copy unchanged.
- **`Spoken coaching`** and **`Help tag songs`** toggle cards — `oraSurface`, radius 16,
  `zoneSteady` tint; keep `Help tag songs` visible-but-disabled with
  `policy.closedReason` shown in `oraWarning` (a toggle that silently does nothing is
  worse than one that explains itself).
- Keep the `hasData == false` empty-state copy.

---

## 4. WHAT IS **NOT** IN THIS PACKAGE
Not yet designed in the new language — do not guess, ask for designs:
`Features/Onboarding/*` (`AuthView`, `MusicSetupSheet`, `PaceSetupView`),
`Features/Library/GoalsView.swift` + `Playlists/`, `LibraryDetailView`,
`Features/Player/NowPlayingView.swift`, `Features/PostRun/LiveRunSummarySheet.swift`,
`Features/Settings/{SettingsView,SubscriptionView,CalibrationView}`,
`Session/LockScreenView` + Live Activity, and the watchOS targets.

They will inherit the token changes in §1 automatically — which is most of the way there —
but their layouts haven't been reviewed against the new system.

## 5. PLACEHOLDER DATA
All numbers, track titles, artists, dates, and the email in the mockups are illustrative
(`Midnight City — M83`, `1,842 of 2,360`, `maya@example.com`, etc.). Bind to the real
stores; don't ship the sample values.

## 6. SUGGESTED ORDER OF WORK
1. `Colors.swift` + `Typography.swift` per §1.1–1.3, and add the two border tokens. Most
   of the app moves in this one commit.
2. Sweep `design: .rounded` → default, and audit every accent use against rule 1.
3. Add the shared pieces: light primary button style, greyscale segmented-control
   appearance, left-accent-rule card, wave-mark + wordmark view.
4. Then the per-screen passes: §2 HUD → §3.2 post-run → §3.1 setup → §3.3 You →
   §3.4/3.5 settings.

## 7. FILES IN THIS PACKAGE
- `README.md` — this spec
- `Dromo Landing Directions.dc.html` — the design reference (open and jump to `7a`, `7b`, `8a`)
- `logo-wave.png` — the wave mark, from the live site
