# Spikes — THROWAWAY (Phase 0 only)

⚠️ **This directory is NOT product code and is NOT part of the Dromo app target.**

XcodeGen's `project.yml` includes only `path: Dromo` (and the test/watch targets), so nothing here is
compiled into the shipping app. These files are disposable feasibility harnesses for Phase 0
(see `../findings/`). Delete them once Phase 0 is signed off.

To run a spike, drop the file into a *separate, throwaway* single-view iOS app and call its entry point:
- `AnalyzabilityProbe.run()` — Task 0.1: which sources yield decoded PCM (run on a real device).
- `BPMEstimatorSpike.validate(against:)` — Task 0.2: BPM accuracy of the recommended Apple-native engine.

Nothing here writes to the server, the schema, or the client app — by Phase 0 rule.
