"""Generate click tracks at exactly-known tempi, to validate the Phase-7 harness.

These are NOT music and NOT evidence about accuracy on real songs — a click track is
the easiest possible input. They exist to prove the instrument end to end (CSV parse →
decode → TrackAnalyzerCore → metrics → report) BEFORE anyone spends hours assembling a
real ground-truth set, so a broken harness is found here rather than there.
"""
import math
import struct
import sys
import wave
from pathlib import Path

RATE = 22050
SECONDS = 40


def kick(n, rate=RATE):
    """A short percussive hit: decaying 65 Hz body + a click transient for a sharp
    onset, which is what spectral-flux onset detection keys on."""
    out = []
    for i in range(n):
        t = i / rate
        env = math.exp(-t * 28)
        body = math.sin(2 * math.pi * 65 * t) * env
        click = math.sin(2 * math.pi * 1800 * t) * math.exp(-t * 220) * 0.5
        out.append(max(-1.0, min(1.0, body + click)))
    return out


def render(bpm, path, seconds=SECONDS, swing=0.0):
    period = 60.0 / bpm
    total = int(seconds * RATE)
    buf = [0.0] * total
    hit = kick(int(0.18 * RATE))

    beat = 0
    while True:
        # `swing` nudges alternate beats to imitate a human drummer's unevenness.
        offset = period * beat + (swing * period if beat % 2 else 0.0)
        start = int(offset * RATE)
        if start >= total:
            break
        for j, s in enumerate(hit):
            if start + j < total:
                buf[start + j] += s
        beat += 1

    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000)) for v in buf))


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    # Spread across the range the engine claims to handle (minBPM 60 … maxBPM 200),
    # plus one uneven "live" feel and one half/double-ambiguous tempo.
    cases = [
        (70.0, "steady", 0.0),
        (90.0, "steady", 0.0),
        (120.0, "steady", 0.0),
        (128.0, "steady", 0.0),
        (140.0, "steady", 0.0),
        (174.0, "octave", 0.0),
        (85.0, "octave", 0.0),
        (160.0, "live-drums", 0.06),
        (100.0, "live-drums", 0.05),
        (180.0, "extreme", 0.0),
    ]
    rows = ["path,true_bpm,difficulty"]
    for bpm, tag, swing in cases:
        name = f"click_{int(bpm)}_{tag}.wav"
        render(bpm, out / name, swing=swing)
        rows.append(f"{name},{bpm:g},{tag}")
    (out / "synthetic.csv").write_text("\n".join(rows) + "\n")
    print(f"wrote {len(cases)} click tracks + synthetic.csv → {out}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "clicks")
