# Findings — User Discovery, Round 1 (3 runners) + the fix list it produced

> **Question this answers:** does the pace-holding pitch land with runners, and what
> does the codebase need before anyone tests it?

## Evidence

Three informal conversations. The pitch used was: *"an app that keeps you within a
pace threshold for training — it vibrates/beeps when you leave it, and changes your
music to speed you up or slow you down."*

| # | Response | Read |
|---|---|---|
| 1 | "Maybe. Most people would — I am not a good model. I'm really bad at pacing, I just go out there and do it. I think most people will try to dial the training… I'm trying to edge more in that direction because it's definitely smarter." | Aspires to structure, has none. Target profile. |
| 2 | "If I was more analytical, yes. But I'm pretty good at consciously knowing my pace. Plus the watch shows me as well." | Names the real competitor: the watch. |
| 3 (follow-up with #1) | Never paid for a coach or any training help. Last run: 2-mile time trial, hoping for sub-6 pace. Hit sub-6 on mile 1, then blew up on a hill in mile 2 — "panting like a dog." | See below. |

## Verdict: **no pivot — reposition, and fix a correctness bug first**

Three conclusions, in descending order of confidence.

### 1. The pitch led with the commodity half
"Vibrates/beeps when you leave the threshold" is a settings toggle on any Garmin or
Apple Watch. Response #2 rejected the product on exactly that basis. The
differentiator — *the music does the correcting, so you don't have to look at your
wrist or decide to obey* — was buried in a subclause. A watch tells you you're wrong
and hands the correction back to you; Dromo closes the loop. That distinction was
never actually tested.

### 2. The engine points at the wrong runner
At hard efforts, runners have excellent feedback — their lungs. Response #2 is
telling the truth about himself. Where amateurs are genuinely bad, and where the
watch genuinely does not help, is **easy days run too hard**: the error is invisible
without a device, and the failure mode is not "I couldn't tell" but "I could tell
and I didn't want to slow down." That is precisely the job for something that
changes the music rather than nagging.

**This is a repositioning, not a pivot.** Same engine, same `BPMAdapter`, same
sequencer — the dominant nudge flips from PUSH to EASE. No architectural change.

### 3. Two things the interviews exposed that no interview could fix
- **Response #3 hit his target and still failed.** Mile 1 was sub-6, which is what he
  wanted. He did not fail to *hold* pace; his target was wrong for two miles with a
  hill in it. Real-time pace feedback cannot fix a bad target — that is a coaching
  problem, and it is the problem he actually had.
- **The hill is a live defect.** See P1 below. On that climb Dromo would have read
  "behind target" and pushed the BPM *up* — telling a redlining runner to go faster.

## Not doing: a social feature

Evaluated and rejected this round. Pre-launch with zero users (the site CTA is still
the waitlist), so any graph is empty on day one. The Global Track Table is
deliberately identity-free (`server/app/models.py`: facts only, ISRC/fingerprint,
`extra="forbid"`, per-user layer explicitly "never here"), and `SupabaseService` is
still a Phase 0 stub — so accounts, a follow graph, per-user server-side run data,
moderation and deletion paths would all be new surface, not a feature. Strava export
already borrows the runners' graph that exists. Revisit only if post-launch retention
shows solo runs don't stick.

---

# The fix list, in order

## P0 — the gate. Nothing below it is trustworthy until this is done.

**0.1 Run the BPM accuracy harness on real music.**
`findings/bpm-accuracy.md` still has blank result tables and no verdict.
`ContributionPolicy.current` is pinned to `.pending`, with a test asserting nothing
publishes. Everything Dromo claims to do differently depends on tempo matching being
correct, and that is currently unmeasured.

- Owner: **Demetri** — needs a device and 25–40 owned tracks with independently
  established BPM. Cannot be done in this environment.
- Instrument is already built: `scripts/validate_groundtruth.py`,
  `findings/groundtruth-template.csv`, `BPMAccuracyHarnessTests`.
- Deliverable: filled Results + By-difficulty tables, a GREEN/YELLOW/RED verdict, and
  `ContributionPolicy.current` changed to match.
- **RED means a core rethink**, not a tweak. Do not build on the assumption of GREEN.

## P1 — correctness bugs that would burn a tester. Fix before anyone runs with this.

**1.1 Grade-adjusted pace — the app currently tells you to speed up on hills.**
`GapCalculator.gap()` is `actual - target` with no grade term, so on a climb the gap
goes positive, `BPMAdapter` reads "behind," and the music accelerates. This is the
exact moment described in interview #3.

Chain to change:
| File | Change |
|---|---|
| `Dromo/Core/Location/PaceSource.swift` | add `altitudeMeters` to `PaceReading` |
| `Dromo/Core/Location/LocationManager.swift:43` | forward `location.altitude` (+ `verticalAccuracy` gate) |
| `Packages/DromoCore/.../Models/PaceLog.swift` | add an altitude field |
| `Packages/DromoCore/.../Engine/GapCalculator.swift:10` | grade term — suppress or invert the push when climbing |
| `Dromo/Core/Session/SessionController.swift:205` | stop hardcoding `altitude: 0` |
| Tests | climb / descent / flat cases in `GapCalculatorTests` |

**1.2 Exports have no elevation.**
`HealthKitManager.swift:64` hardcodes `altitude: 0` into the route builder, and the
GPX writer in `StravaService` emits no `<ele>` element at all. Consequence: every
Dromo run on Strava shows zero elevation gain, and Strava's own grade-adjusted pace
cannot work on our uploads. Falls out of 1.1 once altitude reaches `PaceLog`.

**1.3 Decide what a bad target does.**
Interview #3's failure was an unachievable target, not poor pace-holding. Minimum
viable answer: if the gap stays large and one-directional for N minutes, stop ramping
BPM and say so, rather than pushing a runner who cannot get there. Prevents the app
from spending a whole run nagging someone into the red.

## P2 — repositioning. No engine change; copy, defaults, one setup mode.

**2.1 Easy-run mode in `SessionSetupView`.**
Third option beside target pace and goal time. Target derived as an easy pace; the
dominant nudge is EASE. This is the "stop torching your easy runs" wedge — same code
path, opposite sign.

**2.2 Landing page leads with the differentiator.**
`website/` currently sells the pace threshold. Lead instead with *the music does the
correcting — you never look at your wrist*. The beeping is table stakes and testing
showed it invites a watch comparison we lose.

**2.3 Qualify the waitlist.**
One question on signup — "do you train to a target pace or a goal race time?" — so
every email arrives segmented instead of anonymous. Front-end is a small change in
`website/script.js`; the `waitlist` table needs a new column added in the Supabase
dashboard (the Supabase MCP server is not authorized in the session, so that half is
manual).

## P3 — discovery, round 2. After P1, before any launch push.

**3.1 Re-interview with the easy-run framing**, past-tense questions only: what was
your last easy run, what pace, do you have easy runs at all. If the answer is "I just
go out and do it" — the same phrase interview #1 used about pacing — the wound is
confirmed.

**3.2 Find runners with a goal race time.** Run clubs, first-time half/marathon
groups. A goal finish time means the pacing problem is already felt and named, and
`SessionSetupView` already does goal-time → derived pace.

**3.3 Test willingness to pay explicitly.** Nobody in round 1 had ever paid for
training structure, and RevenueCat is already in the stack on the assumption they
will. Aspiration is cheap; ask what they have actually bought.
