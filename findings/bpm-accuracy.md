# Findings — On-Device BPM Accuracy (Phase 7)

> **Load-bearing question:** how accurate is the on-device BPM detection on *real*
> recordings (not synthetic clicks)? The entire analyze-once-globally architecture
> assumes it's good enough to fill the shared table with correct facts.

## ⚠️ Verdict: **PENDING — requires a real-music measurement run**

The numbers below are **not yet filled in**, and they have **not been fabricated**.
Producing them requires a ground-truth set of real owned tracks, which isn't
available in the authoring environment. The phase's own rules forbid the shortcuts
(no engine-as-ground-truth, no judging by ear, define the bar before measuring) — so
inventing a verdict here would defeat the point. What *is* delivered: the bar (below,
stated up front), the measurement instrument (built + unit-tested), and the exact
procedure to get the numbers.

## The bar — stated BEFORE measuring (do not rationalize after)

Encoded in `DromoCore.AccuracyBar` (defaults below; tune there, not by argument):

| Verdict | Condition |
|---|---|
| **GREEN** | octave-corrected match ≥ **90%** AND median octave-corrected error ≤ **2 BPM** AND confidence predicts error → architecture holds, proceed |
| **RED** | octave-corrected match < **70%** OR high-confidence readings wrong > **20%** → core rethink (3rd-party BPM API for owned tracks, or catalog-forward) |
| **YELLOW** | anything in between → usable *with mitigation*: gate on confidence, fall back to catalog/provider for low-confidence tracks |

- **Match window:** ±2 BPM (octave-corrected); **exact:** ±1 BPM.
- **Octave-corrected** = correct after allowing a ½×/2× reinterpretation (the engine
  can resolve those against cadence at runtime, so they're recoverable; plain errors
  are not). Both raw and octave-corrected numbers are reported.
- **Why median for the GREEN error bar:** robust to a few pathological tracks; the
  difficulty breakdown is what surfaces *where* it fails.

## Task 7.1 — Ground-truth set (you assemble this)

25–40 owned / DRM-free tracks with **independently established** true BPM (published
BPM from a reputable source, or hand-counted over a sustained section — **never** from
this engine). Required hard cases:

| Difficulty tag | What to include | Min |
|---|---|---|
| `steady` | electronic/dance, strong 4-on-the-floor | baseline |
| `live-drums` | rock/pop with a human drummer | several |
| `tempo-change` | slow intro / breakdown / drift | several |
| `octave` | half/double-time-ambiguous (the 85-vs-170 trap) | **≥ 5** |
| `sparse` | acoustic / weak-beat / ambient | several |
| `extreme` | very slow (~70) and very fast (~180+) | a few |

Record true BPM + tag per track in a CSV:

```
path,true_bpm,difficulty
tracks/daft_punk_one_more_time.m4a,123,steady
tracks/zeppelin_levee.m4a,72,live-drums
tracks/dnb_track.m4a,174,octave
...
```

## Task 7.2 / 7.3 — Run the real pipeline + compute metrics

The harness runs the **actual analysis path** (`TrackAnalyzerCore` — the vDSP engine
now wired into the live session) over the set and computes every Task-7.3 metric.
Because the BPM algorithm is identical vDSP on macOS and iOS, **accuracy is measured
faithfully on a Mac**; only per-track battery/CPU needs an on-device run (per-track
time *is* captured here).

```bash
cd Packages/DromoCore
DROMO_BPM_GROUNDTRUTH=/abs/path/groundtruth.csv \
DROMO_BPM_REPORT=$(pwd)/../../findings/bpm-accuracy-results.md \
swift test --filter BPMAccuracyHarnessTests
```

It emits: exact-match rate, octave-corrected match rate, mean/median abs error (raw +
octave-corrected), **error broken down by difficulty tag**, **confidence calibration**
(do low-confidence readings err more?), and **octave-flag recall** (did
`tempo_octave_flag` flag the half/double cases so the engine could resolve them?), plus
the GREEN/YELLOW/RED verdict against the bar above.

### Results (fill from the run)
_PENDING._

| Metric | Value |
|---|---|
| Exact match (±1) | — |
| Octave-corrected match (±2) | — |
| Mean / median abs error (raw) | — |
| Mean / median abs error (octave-corrected) | — |
| High- vs low-confidence error rate | — |
| Confidence predicts error? | — |
| Octave-flag recall | — |
| **Verdict** | **PENDING** |

### Error by difficulty (fill from the run)
_PENDING — this is the table that matters most; an 85% average can hide 50% on `sparse`/`octave`._

## What's built vs. what's gated

| Piece | Status |
|---|---|
| GREEN/YELLOW/RED bar, stated up front | ✅ `AccuracyBar` |
| Metric + verdict computation | ✅ `BPMAccuracy.evaluate` — **7 unit tests** on the math (GREEN/RED/octave/calibration/by-difficulty) |
| Runnable harness over real files (real pipeline) | ✅ `BPMAccuracyHarnessTests` — auto-skips without data |
| Ground-truth set of real owned tracks | ⛔ you provide (copyright + no device here) |
| The actual accuracy numbers + verdict | ⛔ **run the harness** — cannot be produced or guessed here |
| Per-track battery/CPU on-device | ⛔ needs the phone (time is captured cross-platform) |

**Bottom line:** the instrument is ready and trustworthy (its math is tested); the
verdict is intentionally blank until a real run fills it. Do not build further layers
that assume GREEN until this reads GREEN (or YELLOW with the fallback rule wired).
