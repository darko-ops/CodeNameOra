#!/usr/bin/env python3
"""Check a Phase-7 ground-truth CSV BEFORE spending a harness run on it.

Assembling 25–40 tracks with hand-verified BPM is hours of work; discovering
afterwards that six files won't decode, or that the set has only two `octave` tracks,
wastes that work. This checks the set against the requirements in
`findings/bpm-accuracy.md` — Task 7.1 — and says exactly what's missing.

    python3 scripts/validate_groundtruth.py path/to/groundtruth.csv

Exit code 0 = ready to measure, 1 = problems listed above.
"""
from __future__ import annotations

import csv
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

# From the findings doc. `octave` is the trap the whole verdict turns on, so it is the
# only tag with a hard floor; the rest need to be present, not plentiful.
REQUIRED_TAGS = {
    "steady": 1,
    "live-drums": 2,
    "tempo-change": 2,
    "octave": 5,
    "sparse": 2,
    "extreme": 1,
}
MIN_TRACKS, MAX_TRACKS = 25, 40
# The analyzer's own range (OnsetTempoAnalyzer.minBPM / maxBPM).
BPM_FLOOR, BPM_CEIL = 60.0, 200.0


def decodable(path: Path) -> bool:
    """Best-effort decode check. `afinfo` ships with macOS; without it we only
    verify the file exists, and say so rather than implying a deeper check."""
    if not shutil.which("afinfo"):
        return True
    result = subprocess.run(["afinfo", str(path)], capture_output=True)
    return result.returncode == 0


def main(csv_path: str) -> int:
    path = Path(csv_path)
    if not path.exists():
        print(f"✗ no such CSV: {path}")
        return 1

    base = path.parent
    problems: list[str] = []
    warnings: list[str] = []
    tags: Counter[str] = Counter()
    seen: set[str] = set()
    rows = 0
    have_afinfo = shutil.which("afinfo") is not None

    with path.open(newline="") as fh:
        for line_no, row in enumerate(csv.reader(fh), start=1):
            if not row or not row[0].strip() or row[0].strip().startswith("#"):
                continue
            if len(row) < 3:
                problems.append(f"line {line_no}: expected path,true_bpm,difficulty")
                continue
            raw_path, raw_bpm, tag = (c.strip() for c in row[:3])
            if raw_bpm.lower() in {"true_bpm", "bpm"}:      # header
                continue

            rows += 1
            try:
                bpm = float(raw_bpm)
            except ValueError:
                problems.append(f"line {line_no}: true_bpm '{raw_bpm}' is not a number")
                continue

            if not (BPM_FLOOR <= bpm <= BPM_CEIL):
                warnings.append(
                    f"line {line_no}: {bpm:g} BPM is outside the analyzer's "
                    f"{BPM_FLOOR:g}–{BPM_CEIL:g} range — it cannot be detected, only "
                    "octave-corrected"
                )

            audio = Path(raw_path) if raw_path.startswith("/") else base / raw_path
            if raw_path in seen:
                problems.append(f"line {line_no}: duplicate path {raw_path}")
            seen.add(raw_path)

            if not audio.exists():
                problems.append(f"line {line_no}: missing file {audio}")
            elif not decodable(audio):
                problems.append(f"line {line_no}: will not decode: {audio.name}")

            tags[tag] += 1
            if tag not in REQUIRED_TAGS:
                warnings.append(
                    f"line {line_no}: unknown difficulty '{tag}' "
                    f"(expected one of {', '.join(sorted(REQUIRED_TAGS))})"
                )

    if rows < MIN_TRACKS:
        problems.append(f"{rows} tracks — the doc asks for {MIN_TRACKS}–{MAX_TRACKS}")
    elif rows > MAX_TRACKS:
        warnings.append(f"{rows} tracks — more than {MAX_TRACKS}; fine, just slower")

    for tag, minimum in REQUIRED_TAGS.items():
        if tags[tag] < minimum:
            problems.append(
                f"difficulty '{tag}': {tags[tag]} of {minimum} required"
                + (" — this is the tag the verdict turns on" if tag == "octave" else "")
            )

    print(f"{rows} tracks · " + ", ".join(f"{t}={n}" for t, n in sorted(tags.items())))
    if not have_afinfo:
        print("note: afinfo unavailable — checked that files exist, not that they decode")
    for w in warnings:
        print(f"⚠ {w}")
    for p in problems:
        print(f"✗ {p}")

    if problems:
        print(f"\n{len(problems)} problem(s) — fix before running the harness.")
        return 1
    print("\n✓ ready. Run the harness:")
    print("    cd Packages/DromoCore")
    print(f"    DROMO_BPM_GROUNDTRUTH={path.resolve()} \\")
    print("      DROMO_BPM_REPORT=$(pwd)/../../findings/bpm-accuracy-results.md \\")
    print("      swift test --filter BPMAccuracyHarnessTests")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
