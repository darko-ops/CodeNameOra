# Findings — On-Device Analysis Engine (Phase 0, Task 0.2)

> **Question this answers:** Which tempo/feature extractor should Dromo embed for on-device analysis,
> given accuracy, schema coverage, half/double handling, CPU/battery, binary size, and — decisively —
> **license compatibility for a closed-source commercial App Store app**?

## Candidate comparison

| Engine | Lang / embed | License | Added binary size | Tier-1 (bpm, conf, octave, beat_offset) | Tier-2 (energy, beat_strength, drive) | Half/double handling | CPU / battery | Commercial closed-source OK? |
|--------|--------------|---------|:---:|---|---|---|:---:|:---:|
| **AVFoundation + Accelerate (vDSP)** | System frameworks | System (free, no attribution) | ~0 | bpm ✅, confidence ✅, octave ✅ (you flag it), beat_offset ✅ (from onset env) | energy ✅ (RMS), beat_strength ✅ (onset peak ratio), drive ✅ (derived) | **You implement it** (record value + flag) | **Lowest** — HW-accelerated FFT, no extra deps | ✅ **Yes** |
| aubio | C | **GPLv3** | small (~hundreds KB) | bpm ✅, beats ✅→offset, confidence ~ | beat_strength ~, energy ✅ | partial | light | ❌ **No** — GPL incompatible with closed App Store binary |
| Essentia | C++ | **AGPLv3 or paid commercial** | **large** + heavy build (CMake cross-compile, FFTW/Eigen) | `RhythmExtractor2013` → bpm ✅, confidence ✅, beats ✅→offset | energy ✅, beat_strength ✅, key/valence (Tier-3) ✅ | good (built-in) | higher | ⚠️ **Only with paid license** |
| AudioKit / SoundpipeAudioKit | Swift / C | MIT | moderate | FFT/amplitude/pitch only — **no robust offline file BPM/beat-tracking** | partial | n/a | light | ✅ but **insufficient features** |
| Beethoven | Swift | MIT | small | pitch detection only — **no tempo** | ✗ | n/a | light | ✅ but wrong tool |

## Recommendation

**Primary: Apple-native `AVFoundation` + `Accelerate`/vDSP`, with a custom onset-envelope + tempo
pipeline.**

Rationale — **license is the gating constraint** for a commercial closed-source app:
- **aubio (GPLv3)** and **Essentia (AGPLv3)** are both blocked without relicensing or a paid
  commercial license. GPL/AGPL + a closed App Store binary is a non-starter.
- The Apple-native path has **zero license/attribution cost, ~zero binary growth, the best battery
  profile** (hardware FFT), and **direct access** to the exact PCM the OS already hands us for
  analyzable sources (Task 0.1). It can produce **every Tier-1 and Tier-2 field** with implementation
  effort.
- Trade-off accepted: we implement the MIR ourselves (onset detection via spectral flux →
  tempo via autocorrelation/comb-filter → octave flag), so accuracy depends on our tuning rather than
  a battle-tested library. This is the right trade for v1 given the license wall.

**Documented fallback: Essentia under a paid commercial license**, *if* the hand-rolled estimator
can't hit the Tier-1 confidence target on the validation set. Budget-dependent; revisit after the
accuracy check below. **Do not ship aubio.**

### Schema-field coverage of the recommended pipeline (vs ARCHITECTURE §7)
| Field | Produced by Apple-native pipeline? | Method |
|-------|:---:|--------|
| `bpm` | ✅ | autocorrelation/comb-filter peak of onset envelope |
| `bpm_confidence` | ✅ | peak sharpness / ratio of dominant lag to runner-up |
| `tempo_octave_flag` | ✅ | record both candidate (½×/2×) when peaks are ambiguous |
| `beat_offset_ms` | ✅ (v1-optional) | first strong onset position |
| `energy` | ✅ | normalized RMS / loudness |
| `beat_strength` | ✅ | mean onset-peak prominence |
| `drive_score` | ✅ | derived: f(energy, beat_strength, bpm) |
| `key`, `valence` (Tier-3) | ❌ (v1) | would need Essentia / chroma+HPCP work — defer |

## Accuracy validation

A runnable validation harness is provided: `Spikes/BPMEstimatorSpike.swift` →
`validate(against:)` computes per-track error and aggregate stats against a known-BPM set.

### Protocol
1. Assemble 12–15 tracks **you own as DRM-free files** spanning bands: ~90, ~110, ~128, ~140,
   ~150, ~160, ~170, ~175, ~180 BPM, mixed genres, including at least 2 half-time-feel tracks
   (e.g. a 75/150 or 85/170 case) to exercise octave handling.
2. Record each track's **published/known BPM** (from the release, a beat-grid in a DAW, or
   tap-tempo cross-check).
3. Run `BPMEstimatorSpike.validate(against:)`.
4. Record per-track |error|, the octave-flag correctness on the half-time cases, mean abs error,
   and the share within ±2 BPM. Set the **Tier-1 acceptance bar** (proposal: ≥80% within ±2 BPM,
   octave cases correctly flagged) — if unmet, escalate to the Essentia commercial fallback.

### Results
_PENDING — no audio files / no device in the authoring environment. Numbers are **not** fabricated
here (per Phase 0 "do not assume"). Fill this table from a real run:_

| Track (label) | Known BPM | Detected BPM | Octave flag | |error| | Within ±2? |
|---------------|:---:|:---:|:---:|:---:|:---:|
| _…_ | | | | | |

**Mean abs error:** _TBD_ · **Within ±2 BPM:** _TBD%_ · **Octave cases correct:** _TBD_
