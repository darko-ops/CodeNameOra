# Handoff: Dromo — Sound tab rework

## Overview
Dromo is a pace-adaptive running music app (iOS 16+, watchOS 9+). It reads your running
cadence, plays songs from *your own* library whose BPM matches your stride, and nudges
the tempo up/down to keep you on your target pace.

**Sound** is one of the four main tabs (`Home` · `Go` · `Sound` · `You`) — the music home
for the connected service. This package reworks it for organization, discoverability, and
consistency with app design language v2.

**Scope:** one tab. The information architecture changes (section order, one new
sub-screen, one section replaced), but no new backend work — every value shown already
exists in the model layer. Read alongside the v2 language package if you have it; §1 below
lists the tokens this file depends on.

## About the design files
`Dromo Landing Directions.dc.html` is a **design reference created in HTML** — a prototype
showing intended look, not production code. Recreate in SwiftUI using the existing views.

Canvas ids in that file:
- **`9a`** — the diagnosis + the new tempo colour ramp
- **`9b`** — the reorganized Sound tab
- **`9c`** — the new All-tracks screen (searchable, BPM-filtered)

## Fidelity
**High-fidelity.** Colors, type weights, spacing, and radii are final. Old→new values are
given wherever something is being replaced, so you can find every call site.

## Files this touches
```
Dromo/Features/Library/Playlists/PlaylistsView.swift        rewritten (section order + new sections)
Dromo/Features/Library/Playlists/Playlist.swift             PlaylistCatalog accent hexes
Dromo/Features/Library/Playlists/PlaylistsViewModel.swift   + search/filter state, popular → highEnergy
Dromo/Features/Library/Playlists/TrackRow.swift             remove design: .rounded, BPM tint
Dromo/Features/Library/Playlists/PlaylistDetailView.swift   inherits tokens (not redesigned here)
Dromo/Features/Library/Playlists/AllTracksView.swift        NEW
Dromo/Features/Session/SessionSetupView.swift               accept a prefilled target pace
```

---

## 1. TOKENS THIS FILE ASSUMES
From app design language v2. If not yet landed, land these first:

| Token | Value | Was |
| --- | --- | --- |
| `oraBackground` | `#0E1013` | `#080A0E` |
| `oraSurface` | `#16181C` | `#111318` |
| `oraSurfaceElevated` | `#1F2227` | `#1A1F2E` |
| `oraBorder` | `rgba(255,255,255,0.07)` | *(new)* |
| `oraBorderStrong` | `rgba(255,255,255,0.16)` | *(new)* |
| `oraTextPrimary` | `#E7E9EC` | `.white` |
| `oraTextSecondary` | `#9298A1` | `#999999` |
| `oraTextMuted` | `#5B616A` | `#555555` |
| `zoneSteady` | `#6EA8C9` | `#22D3EE` |

Also from v2, and applied throughout this tab:
- **No `design: .rounded`** — system font, `.default` design. `PlaylistsView.trackCell` and
  `TrackRow` both use `.rounded` today; remove both.
- **Light primary buttons** — `#E7E9EC` fill / `#16181C` text.
- **Accent marks live or derived values only.** BPM readouts and suggested paces are
  derived → accent. Track counts, dates, and totals stay `oraTextPrimary`/secondary.
- Cards: `oraSurface` + hairline `oraBorder`, radius 16. Separators inside a card:
  `oraSurfaceElevated`, inset to the content's leading edge.
- Section headers become **10–11pt `.semibold` uppercase, tracking +0.16em,
  `oraTextMuted`** — replacing today's 20pt `.bold` `oraTextPrimary` headers, which
  competed with the nav title and made four shelves look equally important.

---

## 2. WHY THIS REWORK (design ref `9a`)

Today `PlaylistsView` renders four shelves at the same visual weight, in this order:
`Your playlists` (2-col grid, max 6) → `From your library` (h-carousel) → `Popular`
(h-carousel) → `By tempo` (2-col grid). Six problems, and the fix for each:

1. **Tempo is last.** Browsing by intensity is the product's reason to exist and it was
   the final section. → **Move it first.**
2. **A grid hides an ordinal scale.** Warm Up → Easy Miles → Tempo → Threshold →
   Intervals → Sprint Finish is a ramp; a 2-column grid reads left-right-down, so the
   ordering reads as arbitrary. → **One-column ladder.**
3. **`suggestedPaceSecPerKm` was invisible.** `PlaylistCatalog` already assigns each
   bucket a target pace (Warm Up 390 s/km → Sprint Finish 225 s/km) and no UI ever
   showed it. → **Show the pace, and let the row start a run at it.** This is the
   highest-value change: it connects Sound to Go instead of leaving Sound a dead-end
   browser.
4. **A carousel can't browse 1,842 tracks.** `From your library` is a horizontal shelf
   over the entire library with no search and no end. → **Replace with a searchable,
   BPM-filtered list** (`9c`).
5. **"Popular" is mislabeled.** `vm.popular` is
   `source.sorted { $0.energyLevel > $1.energyLevel }.prefix(15)` — nothing to do with
   popularity, and the app has no play-count data from the provider. → **Rename to
   "High energy"** and rename the property `highEnergy`.
6. **Six saturated hues break v2.** `#4FC3F7 #66BB6A #9CCC65 #FFCA28 #FF7043 #EF5350`,
   plus gradient-filled tiles with 38pt white glyphs. But tempo *is* a scale, so it
   earns colour. → **One ordinal ramp, built from tokens v2 already has** (§3).

---

## 3. THE TEMPO RAMP
Replace the `accentHex` values in `PlaylistCatalog.definitions`. Cool = easy, warm =
hard, at matched lightness and chroma so the ladder reads as a single scale:

| Playlist | New | Was | Same as |
| --- | --- | --- | --- |
| Warm Up | `#8FA9C4` | `#4FC3F7` | `zoneWarmUp` |
| Easy Miles | `#85AFC0` | `#66BB6A` | — |
| Tempo | `#7FB09A` | `#9CCC65` | `oraSuccess` |
| Threshold | `#C9A96E` | `#FFCA28` | `oraWarning` |
| Intervals | `#C98A6E` | `#FF7043` | `zonePeak` |
| Sprint Finish | `#C96E6E` | `#EF5350` | `oraDestructive` |

The ramp is deliberately assembled from existing semantic tokens rather than six new
constants — nothing new to maintain, and it stays in the v2 family automatically.

**Drop the gradient tiles.** `LinearGradient(colors: [accent, accent.opacity(0.45)])`
with a 38pt white `systemImage` is replaced by a **3pt × 38pt rounded colour rail** at
the row's leading edge. Keep `systemImage` in the model (playlist detail and any future
grid can still use it); the ladder doesn't need it.

Everything else in `Playlist.swift` is unchanged: `bpmRangeLabel`, `contains(_:)`,
`zone(forBPM:)`, the BPM windows, and the pace values all stay as they are.

---

## 4. THE REORGANIZED TAB (design ref `9b`)
`PlaylistsView.swift`. New order, top → bottom:

### 4.1 Nav + search
Large title `Sound` (26–28pt `.semibold`, tracking −0.03em) on an `oraSurface` bar with a
hairline bottom border. Below it, **a search field** — `oraSurfaceElevated`, radius 11,
`magnifyingglass` in `oraTextMuted`, placeholder **"Search songs, artists, BPM"**.

Use `.searchable(text:)` on the `ScrollView` if you prefer the system treatment; the
mockup draws it inline to show placement. Submitting or typing pushes **All tracks**
(`9c`) with the query applied — the tab's search and the All-tracks search are the same
search, not two.

### 4.2 Enrichment banner (conditional)
Unchanged logic (`coordinator.enrichmentProgress`, shown while `done < total`). Restyled:
`oraSurface` + hairline, radius 12, `ProgressView` tinted `zoneSteady`, copy
**"Building your tempo profile… 1,842/2,360"** with the numerals `oraTextPrimary`
`monospacedDigit()` and the label `oraTextSecondary`.

### 4.3 `RUN BY TEMPO` — the ladder *(was last, now first)*
Header + a one-line explainer: **"Pick an intensity — Dromo sets your target pace to
match."**

One `oraSurface` card, radius 16, containing a row per `vm.tempoPlaylists` entry
separated by inset `oraSurfaceElevated` hairlines. Each row, leading → trailing:

| Element | Spec |
| --- | --- |
| Colour rail | 3 × 38pt, radius 2, `playlist.accent` |
| Name | 16pt `.semibold` `oraTextPrimary` |
| Subtitle | 12pt `oraTextSecondary` — `"\(bpmRangeLabel) · \(tracks.count) tracks"`. For the first bucket render **"Under 125 BPM"**, not `bpmRangeLabel`'s `"0–125 BPM"` (a 0 lower bound is a modelling artifact, not something to show). |
| Pace | 15pt `.bold` `monospacedDigit()`, tracking −0.02em, tinted `playlist.accent`, over a 10pt `/km` in `oraTextMuted`. Formatted from `suggestedPaceSecPerKm`. |
| Go button | 32pt circle, `oraSurfaceElevated`, `play.fill` in `oraTextPrimary` |

**Two distinct targets per row:**
- **Tapping the row** → `PlaylistDetailView(playlist:)` (today's behavior, unchanged).
- **Tapping ▶** → starts a run: switch to the `Go` tab with
  `suggestedPaceSecPerKm` prefilled as the target pace, and this playlist as the
  session's source. `SessionSetupView` needs to accept an optional incoming target pace
  (and honour it over the default) — that is the one non-trivial code change here.

Give the ▶ button its own accessibility label (`"Start run at 6:30 per kilometre"`) so the
two targets are distinguishable to VoiceOver, and keep it ≥44pt in hit area even though
it's drawn at 32.

Below the card, a 12pt `oraTextMuted` caption: **"Tap a row to see its tracks · ▶ starts a
run at that pace."** Drop it once the interaction is established.

### 4.4 `YOUR PLAYLISTS`
Same data (`vm.userPlaylists`), new form: the 2-col grid of 48pt gradient tiles becomes a
compact list in one `oraSurface` card — 40pt `oraSurfaceElevated` tile with
`music.note.list` in `oraTextSecondary`, name 15pt `.semibold`, subtitle
`"\(count) tracks · \(bpm range)"` in `oraTextSecondary`, trailing chevron in
`oraTextMuted`.

The user-playlist accent in `PlaylistsViewModel.reloadUserPlaylists` (`"#22D3EE"`)
becomes `"#6EA8C9"` — or better, stop assigning one: these rows no longer use it.

**`Create playlist` becomes the final row of the same card** (a `plus` tile + label in
`oraTextSecondary`), replacing the full-width `zoneSteady`-on-`oraSurface` button. It's a
low-frequency action and shouldn't carry accent colour or its own block.

Keep the existing `contextMenu` (Rename / Delete), both alerts, and the `prefix(6)` cap —
with a `See all` affordance if there are more than six. Keep the empty-state copy
("No playlists yet — create one for your next session.").

### 4.5 `HIGH ENERGY` *(was "Popular")*
Rename the section and the view-model property (`popular` → `highEnergy`). Keeps the
horizontal shelf — appropriate here, because it's a **capped 15-item editorial shelf**,
not the whole library. Header gets a trailing `See all` in 12pt `oraTextSecondary`.

Cells: 118pt artwork (`TrackArtwork`, radius 14, `oraSurfaceElevated` placeholder), title
13pt `.semibold` 1-line ellipsis, artist 12pt `oraTextSecondary`, BPM 12pt `.semibold`
`monospacedDigit()` in `zoneSteady`. Tapping still calls
`nowPlaying.play(tracks:startAt:)`. Remove `design: .rounded` from the BPM label.

### 4.6 `All tracks` — entry point *(replaces the "From your library" carousel)*
A single left-accent-rule card (`oraBorderStrong` 2pt leading edge): title **"All tracks"**
15pt `.semibold`, subtitle **"1,842 tagged · browse and filter by BPM"** (count
`monospacedDigit()`), trailing chevron. Pushes `9c`.

---

## 5. ALL TRACKS (design ref `9c`) — new screen
New file `AllTracksView.swift`. This is where the library actually becomes browsable.

- **Nav:** back to `Sound`, inline title `All tracks`, `oraSurface` bar + hairline.
- **Search field:** same styling as the tab's; active state shows the query with a
  `zoneSteady` caret and a clear (`✕`) button in `oraTextMuted`. Matches title **and**
  artist; also accept a bare number as a BPM query (e.g. `168` → tracks at 166–170).
- **BPM filter chips:** horizontally scrolling row, `All BPM` first then one chip per
  `PlaylistCatalog` bucket (`<125`, `125–140`, `140–152`, `152–164`, `164–176`, `176+`).
  Each unselected chip is `oraSurface` + hairline with its label in **that bucket's ramp
  colour**, so the filter row and the tempo ladder are visibly the same taxonomy.
  Selected chip: light fill (`#E7E9EC` / `#16181C`). Single-select. Reuse
  `PlaylistCatalog` windows — do not hardcode the ranges again.
- **Result bar:** `"\(n) results"` in `oraTextSecondary` (count `monospacedDigit()`) with
  a trailing sort control, default **`BPM ↑`** (alternatives: Title, Artist). Sorting by
  BPM by default is the point of the screen.
- **Rows:** reuse `TrackRow` — 46pt artwork (radius 9), title 15pt `.semibold`, artist
  12pt `oraTextSecondary`, trailing BPM 15pt `.bold` `monospacedDigit()` over a 9pt `BPM`
  label. **The BPM value is tinted with its bucket's ramp colour**
  (`PlaylistCatalog.zone(forBPM:)` already returns it) rather than a flat `zoneSteady` —
  so tempo is legible while scanning. Row background `oraSurface`, separators inset
  `oraSurfaceElevated`.
- **Untagged tracks** (`track.bpm == 0`): show them, with the title in `oraTextSecondary`
  and **"No tempo yet"** in `oraTextMuted` where the BPM would be. Don't hide them — the
  user knows they own the song, and silently omitting it looks like a bug. They sort last
  under `BPM ↑` and are excluded by any BPM filter.
- Tapping a row plays it in context via `nowPlaying.play(tracks:startAt:)` — passing the
  **current filtered/sorted array**, so the queue matches what's on screen.
- **Empty states:** no query match → "No tracks match "daft"."; a BPM filter with no
  results → "Nothing in your library at this tempo yet." Both `oraTextSecondary`, centered.
- The `MainTabView` mini-player overlays this screen as normal.

---

## 6. VIEW-MODEL CHANGES
`PlaylistsViewModel`:
- Rename `popular` → `highEnergy` (logic unchanged: sort by `energyLevel`, `prefix(15)`).
- Add `@Published var query: String = ""` and
  `@Published var bpmFilter: (lower: Double, upper: Double?)?`.
- Add a derived `filteredTracks: [Track]` applying query → BPM window → sort. Debounce
  the query ~200ms; `libraryTracks` can be thousands of rows.
- `libraryTracks` stays as-is (All tracks reads from it); it is simply no longer rendered
  as a carousel.
- The `MockMusicCatalog` fallback and everything in `load(from:)` is unchanged.

Nothing changes in `PlaylistRepository`, `Track`, `TrackArtwork`, or `NowPlayingController`.

---

## 7. ACCESSIBILITY
- ▶ and the row are separate actions with distinct labels (§4.3).
- Don't rely on the ramp alone: every tempo row and every BPM readout carries its number
  in text, and the chips are labelled with their ranges. The colour is redundant encoding.
- The ramp's mid-tones sit ≈4.5:1 on `#16181C`; keep colour on **numerals and rails**,
  never on body copy.
- Support Dynamic Type — the ladder rows should grow vertically rather than truncate the
  pace.

## 8. PLACEHOLDER DATA
All titles, artists, counts, and totals in the mockups are illustrative (`Daft Punk`
results, `1,842 of 2,360`, `Sunday Long Run`, per-bucket track counts). Bind to the real
stores. The **BPM windows and the six pace values are real** — from
`PlaylistCatalog.definitions`.

## 9. SUGGESTED ORDER OF WORK
1. `PlaylistCatalog` accent hexes (§3) — one line each, instantly visible.
2. Section reorder + restyle in `PlaylistsView` (§4.1–4.5), including dropping
   `design: .rounded` and the gradient tiles.
3. `AllTracksView` + the view-model search/filter state (§5–6), then swap the
   `From your library` carousel for the entry-point card (§4.6).
4. The ▶ → `Go` hand-off with a prefilled target pace (§4.3) — the only change that
   reaches outside this tab.

## 10. FILES IN THIS PACKAGE
- `README.md` — this spec
- `Dromo Landing Directions.dc.html` — the design reference (open and jump to `9a`, `9b`, `9c`)
