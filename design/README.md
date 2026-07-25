# Handoff: Dromo — Website landing redesign + in-app running HUD

## Overview
Dromo is a pace-adaptive running music app (iOS 16+, watchOS 9+). It reads your
running cadence, plays songs from *your own* library whose BPM matches your stride,
and nudges the tempo up/down to keep you on your target pace.

This handoff covers two things designed in this project:
1. **Marketing landing page** (dromo.fit) — a redesign of the existing static site.
2. **In-app live running screen** (the HUD shown during a run).

All work lives in a single design-reference file: `Dromo Landing Directions.dc.html`.
It is organized as stacked "turns" (newest at top) on a pan/zoom canvas.

## About the design files
The file in this bundle is a **design reference created in HTML** — a prototype
showing intended look and behavior, **not production code to ship directly**. The
task is to **recreate these designs in the target codebase**:
- The **landing page** → the existing static site (`website/` in the Dromo repo:
  `index.html` + `styles.css` + `script.js`, no build step). Recreate with the same
  dependency-free approach.
- The **in-app HUD** → SwiftUI, matching the existing app design system
  (`Dromo/Shared/DesignSystem/`) and the existing `ActiveSessionView` / `LiveHUDView`
  view structure.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, copy, and animation timings are
specified below and should be recreated pixel-accurately using the codebase's
existing patterns.

---

## CHOSEN DIRECTION

Two design systems are in play, on purpose:

- **Marketing site → "Minimal" system** (design ref `4a` desktop, `5a` mobile).
  Mostly greyscale on near-black, with blue pulled *way* back to a single subtle
  accent. Simpler typeface (Helvetica/Neue), lighter weights. Features a **DRØMO
  "unlock" intro animation** on load.
- **In-app HUD → app zone-color system** (design ref `6a` on-pace, `6b` speed-up).
  Color here is **functional** (the whole screen tints to the coaching status), so it
  keeps the app's full vibrant zone palette — this is intentionally *not* greyscale.

Other explorations exist in the file for reference only and are **not** the chosen
direction: `1a` refined-dark, `1b` tempo-editorial, `1c` pace-zones (color),
`2a/2b/2c` font studies, `3a` pace-zones-in-Archivo.

---

## DESIGN TOKENS

### Marketing "Minimal" system (landing page — `4a`/`5a`)
```
Color
  --bg            #0E1013   page background (near-black)
  --surface       #16181C   cards, inputs
  --surface-alt   #121417   alternating section background
  --border        rgba(255,255,255,0.07)   hairline borders
  --border-strong rgba(255,255,255,0.16)   card top-accent rule
  --text          #E7E9EC   primary text
  --text-2        #9298A1   secondary text / body
  --text-3        #5B616A   muted labels, placeholders
  --accent        #6EA8C9   SUBTLE steel-blue — used sparingly only:
                            Ø logo slash, "on target" dot, "PEAK" label,
                            meter tip, STEP labels, "pace" word in hero H1
  --btn-fill      #E7E9EC   primary button background (light grey)
  --btn-text      #16181C   primary button text

Typography
  Family:  "Helvetica Neue", Helvetica, Arial, sans-serif
  Weights: 500 (nav), 600 (headings/labels/buttons), 700 (logo/hero)
  Hero H1:        4.6rem / weight 700 / line-height 1.02 / letter-spacing -0.03em
  Section H2:     2.5rem / 700 / -0.02em
  CTA H2:         3rem / 700
  Card H3:        1.12–1.2rem / 600
  Body:           1.0–1.18rem / 400–500 / line-height 1.5–1.55, color --text-2
  Eyebrow:        0.8rem / 600 / uppercase / letter-spacing 0.18em / --text-2
  Step label:     0.78rem / 600 / letter-spacing 0.14em / --accent

Radius
  buttons/inputs/pills: 999px
  cards:                16px
  meter/track:          999px

Spacing
  Section vertical padding: 76px (desktop), 34px (mobile)
  Screen horizontal gutter: 44px (desktop), 22px (mobile)
  Card padding: 28–32px (desktop), 18–20px (mobile)
  Content max-width: 1080px; card page max-width: 1180px
  Grid gaps: 22px (desktop cards), 12px (mobile)
```

### App zone-color system (in-app HUD — `6a`/`6b`)
Exact hex from `Dromo/Shared/DesignSystem/Colors.swift`:
```
  oraBackground        #080A0E
  oraSurface           #111318
  oraSurfaceElevated   #1A1F2E
  zoneWarmUp           #4FC3F7   blue      → "EASE" / too-fast nudge
  zoneSteady           #22D3EE   aqua      → "ON PACE" / hold nudge (primary accent)
  zonePeak             #FF7043   orange    → "SPEED UP" / too-slow nudge
  zoneRecovery         #CE93D8   purple    (not used on these screens)
  oraTextPrimary       #FFFFFF
  oraTextSecondary     #999999
  oraTextMuted         #555555
  oraSuccess           #4CAF50
  oraWarning           #FF9800   → "Off-beat" feedback control
  oraDestructive       #F44336   → "End" button
Typography: SF system font, .rounded design for numbers/status/nudge (weights
  .semibold/.bold/.black). In the HTML ref this is approximated with "Nunito".
Radius: nudge badge 18, now-playing card 16, buttons 12, art tile 10.
```

---

## SCREENS / VIEWS

### 1. Landing page — desktop (design ref `4a`)
**Purpose:** Convert visitors to the email waitlist; explain the pace-adaptive concept.
**Layout:** Single column, centered content (max-width 1080px), full-width dark
sections stacked vertically. Sticky-feel top nav.

Sections top→bottom:
1. **Nav** (height 74px, gutter 44px, bottom hairline border): left = **DRØMO**
   wordmark; right = text links "How it works", "Features", "Privacy" (--text-2) +
   pill button "Join the waitlist" (--btn-fill / --btn-text, 600).
   - Wordmark: the letters `DR` + `Ø` + `MO`, weight 700, letter-spacing 0.04em.
     The **Ø** is an `O` with an absolutely-centered 2px `--accent` slash rotated
     -45°, width 1.15em.
2. **Hero** (padding 84px top): centered. Eyebrow → H1 "Your library, locked to
   your **pace**." (the word "pace" is --accent, everything else --text) → sub
   paragraph (--text-2, max 540px) → inline email capture (input pill + "Get early
   access" button, max 460px) → **cadence meter card** (see component below).
3. **How it works** ("Three numbers, perfectly in sync"): H2 + lede, then 3 cards in
   a `repeat(3,1fr)` grid, gap 22px. Each card: --surface bg, hairline border, a 2px
   `--border-strong` top rule, radius 16, padding 32×28; contains a --accent STEP
   label, an H3, and a --text-2 paragraph. Copy:
   - STEP 01 · "It reads your stride" · "GPS pace and pedometer cadence tell Dromo
     how fast your feet turn over — live."
   - STEP 02 · "It matches the tempo" · "Tracks from your own library whose BPM lands
     on your cadence."
   - STEP 03 · "It keeps you honest" · "Off target? The tempo eases up or down to pull
     your pace back."
4. **Built for the run** (--surface-alt bg, top+bottom hairline): H2 + 3×2 grid of 6
   feature cards (--bg, radius 16, padding 28×26). Each card: a 42px icon chip
   (rgba(255,255,255,0.06) bg, radius 11) holding a **desaturated emoji**
   (`filter: grayscale(1) brightness(1.5)`), an H3, a --text-2 paragraph. Cards:
   - ⚡ Real-time pace lock · "Hands-free tuning from the first step to the last."
   - 🎧 Your own music · "Apple Music, re-sorted by tempo instead of by album."
   - 🎯 Pace targets & goals · "A goal pace or race time becomes a cadence to hit."
   - 📈 Momentum that builds · "Streaks and a tempo profile that sharpens as you run."
   - ⌚ Glanceable HUD · "Pace, cadence, now-playing — and on your wrist."
   - 🔒 Privacy by design · "Only numbers leave your phone — never your audio."
5. **Testimonials** ("Runners are already hooked"): H2 + lede + 3 `<figure>` cards
   (--surface, radius 16, padding 30×28). Each: an oversized `"` quote glyph
   (--text-3), a blockquote (1.06rem), and a figcaption = 40px round avatar
   placeholder (#2A2E34) + name (600) + detail (--text-3, 0.82rem).
   **NOTE: testimonial names/quotes/PRs are placeholder — replace with real ones.**
6. **Final CTA** ("Be first on the start line"): centered H2 (3rem) + paragraph +
   email capture (identical to hero).
7. **Footer** (top hairline, padding 38×44, space-between): DRØMO wordmark left,
   "© 2026 Dromo · dromo.fit" (--text-3) right.

### 2. Landing page — mobile (design ref `5a`)
Same content, single-column, ~390px screen. Differences from desktop:
- Email capture stacks vertically (input then button, full width).
- How-it-works steps become a vertical stack; each step card uses a 2px **left**
  border accent instead of a top rule.
- Features become a 2-column grid (shortened copy).
- Testimonials reduced to one card.
- Nav shows the wordmark + a 2-line hamburger (two 19×2px --text-2 bars).
- Type scales down: hero H1 2.5rem, section H2 1.6rem, CTA H2 1.9rem.
- Includes an iOS status bar row ("9:41" + status glyphs) under the notch.

### 3. In-app running HUD (design ref `6a` on-pace, `6b` speed-up)
**Purpose:** Hands-free live run screen. Zero taps required; readable at a glance.
Recreate as SwiftUI matching existing `ActiveSessionView`/`LiveHUDView`.
**Layout:** Full-screen `oraBackground`, safe-area padding, a vertical stack:
1. Top row: elapsed context left, **"End"** (oraTextSecondary, 15 semibold) top-right.
2. **Nudge badge** — full-width, radius 18, background = `nudgeColor.opacity(0.12)`,
   centered label in `nudgeColor`, ~34pt bold rounded. Text + color by state:
   - hold → "ON PACE" / zoneSteady #22D3EE
   - speedUp → "SPEED UP" / zonePeak #FF7043
   - slowDown → "EASE" / zoneWarmUp #4FC3F7
   Subtitle below (oraTextSecondary) = gap description ("You're right on target" /
   "15 s/km behind — pick up the pace" / etc.).
3. **Pace block** — 3 metrics in a row (dividers between): PACE (colored by
   nudgeColor), TARGET (white), TIME (white). Values 26pt bold rounded, **tabular /
   monospaced digits**; labels 10–11pt medium, oraTextMuted.
4. **Cadence** — small centered "CADENCE" label + "168 spm".
5. **Target-BPM bar** — label row "TARGET BPM" + value (nudgeColor); a
   `oraSurfaceElevated` track (radius 999, height 10) with a fill up to the target
   position within the runner's minBPM…maxBPM range (fill gradient warmup→current
   zone color); min/max ticks below. When behind pace, the target ramps up (e.g. 174)
   and the fill gradient trends toward zonePeak.
6. **Now-playing card** — `oraSurface`, radius 16, padding: a 52px art tile
   (`oraSurfaceElevated`, radius 10, music-note glyph), title (16 semibold, 1 line,
   ellipsis) + artist (13, oraTextSecondary), and a right-aligned BPM readout (20 bold
   rounded, nudgeColor + "BPM" 9pt muted). Fallback title "Finding your tempo…".
7. **Feedback controls** — row of 3 vertical icon+label buttons:
   - Like (thumbsup) / zoneSteady
   - Off-beat (metronome) / oraWarning #FF9800
   - Skip (forward.end) / oraTextSecondary
   Disabled + 0.4 opacity when no track is playing.
8. **Pause / End** — two equal buttons: "Pause" (pause glyph) on oraSurfaceElevated
   radius 12; "End" on `oraDestructive.opacity(0.2)` with oraDestructive text.

**Pace-deviation alert (state `6b`):** while the runner is outside the ±20 s/km band,
a **radial glow** fills the screen in the direction's tint (too-slow → zonePeak,
too-fast → zoneWarmUp) plus a centered message: an icon (hare for too-slow / tortoise
for too-fast), a ~44pt black title ("TOO SLOW" / "TOO FAST"), and a semibold subtitle
("Pick up the pace" / "Ease off"). The overlay is non-interactive
(`allowsHitTesting(false)`), transitions in via opacity, and pairs with an audio beep
that repeats every 30s while out of range.

---

## INTERACTIONS & BEHAVIOR

### Landing page
- **Email waitlist forms** (hero + final CTA): validate against
  `^[^\s@]+@[^\s@]+\.[^\s@]+$`. On submit, disable button (show "…"), POST to the
  existing Supabase `waitlist` table (insert-only public key; see existing
  `website/script.js` — reuse it verbatim). Success → "You're on the list — we'll be
  in touch. 🏃" (success color); duplicate (409) treated as success; error → "Something
  went wrong. Please try again." Note reverts after 6s.
- Buttons: subtle lift on hover (`translateY(-2px)`), 0.2s ease.
- Footer year auto-set to current year.
- Respect `prefers-reduced-motion`: disable the intro animation and any looping motion.

### DRØMO unlock intro (landing page, on load) — design ref `4a`/`5a`
A dark sheet (`#0B0D10`) covers the page on load, holding the DRØMO wordmark centered
near the top. Timeline (all start on mount; slowed timing is the chosen final):
```
  Ø slash:   rotate 0 → 720°     2.6s  cubic-bezier(.5,0,.25,1)  delay 0.2s
  "DR":      translateX 0 → -820px (desktop) / -320px (mobile), opacity→0
                                  1.2s  cubic-bezier(.7,0,.25,1)  delay 1.7s
  "MO":      translateX 0 → +820px / +320px, opacity→0   (same timing as DR)
  Overlay:   opacity 1 → 0, then visibility hidden   0.9s ease  delay 2.9s
  Page:      opacity 0→1, blur(12px)→0, scale(1.03)→1  1.1s ease  delay 2.9s ("both")
```
Net: slash spins during the hold → DR flies left / MO flies right → the sheet fades as
the page resolves out of a blur ("unlock"). The prototype adds a "↻ Replay intro"
button for review; production plays once per load (gate with sessionStorage if you
don't want it on every navigation) and must no-op under reduced-motion.

Intro logo Ø: `O` with an absolutely-centered slash — desktop 5px tall / 6rem letters;
mobile 4px / 3.2rem letters; slash is `--accent` #6EA8C9, radius 3, rotated via the
spin keyframe (base `translate(-50%,-50%) rotate(0)`).

### In-app HUD
- Fully driven by a live 1 Hz loop (`LiveSessionViewModel` / `LoopState`); **no taps
  required**. State changes animate: nudge badge `easeInOut 0.3s`; now-playing card
  swap `easeInOut 0.4s`; pace-alert overlay `easeInOut 0.4s`.
- Like → private taste store, re-weights selection live. Skip → advance track now.
  Off-beat → flags tempo to the Global Track Table. Pause/Resume toggles; End finishes
  and routes to the post-run summary.

---

## STATE MANAGEMENT

### Landing page
- Form: `email` (string), `submitting` (bool), `noteState` (default | success | error).
- Intro: `showIntro` (bool, true on mount; the prototype toggles it off→on to replay).
  Independent flag per breakpoint in the prototype (`showIntro` desktop,
  `showIntroM` mobile) — production needs just one.

### In-app HUD
Mirror the existing `LoopState`:
`currentPaceSecPerKm`, `targetPaceSecPerKm`, `currentCadence`, `targetCadence`,
`nowPlayingTrackID`, `nowPlayingBPM`, `nudge` (speedUp|hold|slowDown), plus the
standing `paceAlert` (nil | tooSlow | tooFast) from `PaceAlertMonitor`. Nudge color and
all colored elements derive from `nudge`; the alert overlay derives from `paceAlert`.

---

## ASSETS
- **No raster assets required.** The old brand equalizer-bars logo is replaced by the
  **DRØMO wordmark** (pure type + a CSS/SwiftUI slash for the Ø).
- Feature icons are emoji (⚡🎧🎯📈⌚🔒) rendered desaturated via a grayscale filter on
  the landing page. In the app, use SF Symbols (bolt/headphones/target/chart/watch/
  lock) tinted to match.
- Album art / avatars are neutral placeholders (#1A1F2E / #2A2E34) — real album art and
  real testimonial photos to be supplied.
- Fonts: "Helvetica Neue"/Helvetica (landing); SF system rounded (app). The HTML ref
  loads Nunito to approximate SF-rounded — do not ship Nunito in the app.

## FILES
- `Dromo Landing Directions.dc.html` — the design reference (all turns). Relevant
  sections: `4a` (landing desktop, chosen), `5a` (landing mobile, chosen),
  `6a`/`6b` (in-app HUD, chosen). `1a/1b/1c`, `2a/2b/2c`, `3a` are earlier
  explorations, not the chosen direction.
- Existing Dromo repo references to match: `website/{index.html,styles.css,script.js}`,
  `Dromo/Shared/DesignSystem/Colors.swift`, `Dromo/Features/Session/{ActiveSessionView,
  LiveHUDView,LiveSessionViewModel}.swift`.
