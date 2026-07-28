# Instrument check — the Phase-7 harness itself (NOT the accuracy verdict)

**This file contains no evidence about accuracy on real music.** The Phase-7 verdict in
`bpm-accuracy.md` stays **PENDING** until the harness is run over an owned ground-truth
set. What follows is a check of the *measuring device*, run on synthetic click tracks,
so that a broken harness is discovered here rather than after someone has spent hours
assembling 25–40 real tracks with hand-verified BPM.

Click tracks are the easiest input that exists: perfectly periodic, one timbre, no
mix, no dynamics. Reading them as an accuracy result would be like calibrating a scale
with a 1 kg weight and reporting "this scale weighs everything correctly".

## What was run

10 generated WAVs (22.05 kHz mono, 40 s), one per tempo across 70–180 BPM, through the
**real** command from `bpm-accuracy.md` — same env vars, same `BPMAccuracyHarnessTests`,
same `TrackAnalyzerCore`:

```bash
cd Packages/DromoCore
DROMO_BPM_GROUNDTRUTH=<scratch>/clicks/synthetic.csv \
DROMO_BPM_REPORT=<scratch>/instrument-check.md \
swift test --filter BPMAccuracyHarnessTests
```

Generator: `scripts/make_click_tracks.py` (kick = decaying 65 Hz body + click transient;
`swing` displaces alternate beats to crudely imitate an uneven human drummer).

## What it proves — the harness works end to end

| Stage | Result |
|---|---|
| CSV parsing (header skip, relative paths) | ✅ 10/10 rows resolved |
| Decode path (`AVAssetReader` → mono 22.05 kHz float) | ✅ 10/10 decoded |
| `TrackAnalyzerCore.analyze` over real PCM | ✅ 10/10 produced a reading |
| Metric computation + by-difficulty breakdown | ✅ tables populated |
| Report written to `DROMO_BPM_REPORT` | ✅ file written |
| Per-track timing captured | ✅ 276–1279 ms per 40 s track (Mac) |

The instrument is sound. When the real set exists, the run will produce numbers.

## Two observations worth carrying INTO the real run

Neither is a verdict. Both are hypotheses the real set should test.

**1. An uneven beat produced an UNFLAGGED half-tempo reading.** Isolated deliberately,
same tempo, only evenness changed:

| Input | True | Detected | Octave flag |
|---|---|---|---|
| 160 BPM, perfectly even | 160 | **160.9** | none |
| 160 BPM, alternate beats displaced 6% | 160 | **80.4** | **none** |

The half-tempo reading itself is ordinary — octave error is the known trap, and
`SelectionEngine.effectiveBPM` exists to resolve it. What matters is that the flag said
`none`: the engine only considers alternatives the flag permits, so this reading is
unrecoverable at selection time and would pace a 160 spm runner to an 80 BPM track.
By contrast the 180 BPM case read 89.5 *with* `double`, which the engine resolves
correctly — that is the system working.

Caveat: 6% swing on a click track is a crude proxy for a human drummer; real music also
varies in amplitude and timbre, which may help or hurt. This says *where to look*
(`live-drums`, `octave` tags), not what will be found.

**2. Confidence saturated at 1.0 on every track, including the wrong one.** Hence
"Confidence predicts error? **no**". On trivially-periodic input, high confidence is
arguably honest. But the YELLOW mitigation in the bar — *gate on confidence, fall back
to the lookup chain for low-confidence tracks* — only works if confidence discriminates.
If the real run also shows confidence pinned near 1.0 on wrong readings, that mitigation
is unavailable and the YELLOW branch needs rethinking before Phase 4.

## What this check cannot tell you

- Accuracy on real music — mixes, vocals, bass-heavy masters, ambient, tempo drift.
- Whether `octave` and `sparse` tracks pass the bar; those are the tags the verdict
  turns on and neither is meaningfully represented by a click.
- Anything about the device: battery, thermals, or `assetURL` availability
  (see `ios-analyzability.md`).

The harness also printed a verdict line for this synthetic set. It is meaningless as a
product signal and is deliberately not reproduced here.
