# Aircraft 5 sustained gunnery baseline

> Superseded for long-run pursuit conclusions: the follow-up investigation found
> that this first harness did not rebase its scripted target path when the world
> origin moved. It also used kinematic freeze, which could report a fictitious
> target velocity during a rebase. The kilometre-scale range jumps below are
> test artifacts, not proof of AI failure to close. Preserve these results as
> historical data; see `GUNNERY_PURSUIT_DIAGNOSIS_2026-09-09.md` for validation
> and replacement runs. Exact hit totals from this version are not a clean
> post-fix comparison baseline.

## Test design

Run `Scenario/GunneryTrackingBaseline.tscn` headlessly at 60 fixed frames/s.
Six cases, each with a fresh production Aircraft 5 and 180 simulated seconds:
tail chase, left/right crossings, gentle left circle (480 m radius at 84 m/s),
and tight left/right circles (220 m radius at 80 m/s). Start altitude 1000 m,
below the authored 1400 m preferred combat ceiling; no terrain scene is loaded.
The target is a frozen kinematic 4 m-radius sphere with an explicit no-damage
health contract. Real bullet collisions still generate hit reports and damage
event counts. Targets remain present throughout the case plus an 8-second
projectile-report drain. They do not evade or shoot back.

All 185 dogfight settings are preserved, including pursuit/precision gains,
turn feedback, collision avoidance and tactical ceiling. The real cannon keeps
its authored 0.35-degree spread. Test-only exceptions: no carrier-distance leash,
no health/fuel RTB threshold, selected guns, gear stowed, and 1,000,000 rounds per
gun. This is a controlled tracking baseline, not an unrestricted combat win rate.
The existing optimizer and production AI/fire authorization are unchanged.

## Measurements

- Angular error from the current gun direction to a fresh ballistic solution.
- Total/longest continuous time within 1 degree AND 900 m; acquisition requires
  at least 0.5 seconds continuously within that envelope.
- Current-bore projected miss at the solved intercept time; time within the
  target's 4 m radius. This uses the pilot's motion model and is an estimate,
  not a promise that a spread-affected bullet will hit.
- Actual shots and projectile hit/miss reports, including reports during drain.
- 30-second tracking blocks, RMS/p95 angular error, roll-input reversals,
  aircraft states, 10 Hz tracking traces and inherited 1 Hz controller traces.
- Per-case settings, target health and selected source-file hashes.

Legacy `solution_fraction`, `ballistic_quality`, `fitness` and related fields
are retained for comparison only. They include the old ideal-aim heuristic and
must not be treated as observed accuracy or used to optimize this baseline.
Block hit deltas are arrival-time counts; overall hits/shots include the drain.

## Verification / runs

`GunneryTrackingBaselineSmoketest.tscn` PASS: 1,000 large damage calls do not
reduce target health; 185 dogfight settings and gun spread are preserved.
Use `--scene`, not `--script`, because the production scene has autoload-dependent
scripts. The five-second shot sanity check produced 17 hits from 18 shots/reports,
all 17 damage events counted, target health still 100/100. This is not the baseline.

`gunnery_tracking_20260909_141842` was stopped during setup validation after its
first completed case: the inherited 2600 m starting altitude was above the combat
ceiling. Its partial logs are preserved and excluded from the baseline.

Corrected full run: `gunnery_tracking_20260909_142108`, COMPLETE.
Output: `user://gunnery_tracking_20260909_142108.json`; paired stdout/stderr logs
use the same prefix. Results are written after each case and at completion.

## Results

Each case completed 180 seconds (approximately 179 measured after warmup).
All targets remained alive at 100/100 health, no case was invalid, and selected
input hashes remained unchanged. All 205 physical shots produced reports;
48 hit the target. Visual-only tracer rounds are not counted as physical shots.
No script errors were found in this completed run; camera interpolation warnings
were present. This is one seeded run per pattern, not a broad success-rate study.

| Pattern | Hits / shots | Total within 1 degree and 900 m | Longest continuous hold |
| --- | ---: | ---: | ---: |
| Tail chase | 48 / 69 | 15.08 s | 7.50 s |
| Crossing left | 0 / 54 | 0.92 s | 0.75 s |
| Crossing right | 0 / 59 | 0 s | 0 s |
| Gentle left turn | 0 / 2 | 0 s | 0 s |
| Tight left turn | 0 / 0 | 0 s | 0 s |
| Tight right turn | 0 / 21 | 0 s | 0 s |

In the tail chase, 47 hits arrived in the first 31 seconds and just one afterward.
By approximately 61 seconds, range had opened to 4 km despite remaining in
DOGFIGHT; by 161 seconds it was over 9 km. Gentle-turn trace samples show large
off-nose errors (approximately 79 degrees at 31 seconds), not just fine sight jitter.

Next diagnosis should compare commanded versus actual turn/track rates and
closure-speed control through acquisition, overshoot and rejoin. These results
suggest pursuit and keeping a firing position are the first bottlenecks; they
do not yet identify which controller term is responsible. Do not increase gains
or optimize the old ideal-aim fitness before establishing that cause.
