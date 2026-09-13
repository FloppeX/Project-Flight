# Dogfight separation and capture follow-up

Later investigation and results: `DOGFIGHT_GROUND_PROBE_AND_ESCAPE_2026-09-09.md`.
It identifies a false terrain-crash mechanism in airborne traffic; older non-gun
losses below should not all be assumed to be physical collisions.

Follow-up to `DOGFIGHT_VISUAL_TRACKING_RESULTS_2026-09-09.md`. Changes are limited
to pilot control/tactics, the opt-in duel observer, and regression tests. No
airframe mass, thrust, drag, lift, weapon damage or landing behavior was retuned.

## What changed

1. Combat avoidance now owns separation from the current opponent continuously.
   The slower general traffic override no longer interrupts that maneuver with
   separate open-loop roll/pitch inputs. General avoidance still handles other
   contacts; terrain protection still takes priority.
2. Closest-approach prediction rejects negative times and encounters beyond its
   configured three-second horizon instead of clamping them into the window.
   Previously, an already-receding pass could trigger a new break, and an encounter
   outside the horizon could suppress an otherwise useful firing opportunity.
   Actual proximity still triggers the hard separation floor, including co-speed
   contacts with almost no relative velocity.
3. The committed break uses horizontal flight-path right and the observed threat
   position. It turns away regardless of current bank. Reciprocal head-on ties
   turn to each aircraft's own right. Opposite vertical offsets (bounded to 90 m
   away from low terrain) help prevent similar horizontal paths remaining at the
   same height. Near terrain, descending separation is prohibited.
4. The existing pursuit/reset behavior is retained, with an additional forward
   stalemate test: a visible off-center target with almost unchanged angle/range
   and no useful firing position for 25 seconds can trigger a committed reset.
   Normal capture, recent gun opportunities and changing geometry do not satisfy
   this new stagnant-forward condition.
5. A small speed reserve is allowed only during precise tracking of an observed
   turning target, when target and own velocity directions differ substantially.
   Radial target speed alone understates the speed needed to follow its curved
   path. Straight crossing captures keep their existing braking schedule.

Knowledge remains based on observed tracks for these combat helpers. There are
no teleports, direct attitude changes, force cheats or target-truth steering in
the new maneuvers. The general non-target traffic sensing system was not redesigned.

## Changes tested and rejected

- An aggressive progress timer and an eight-second trailing re-intercept phase
  destroyed both 90-second crossing-target regressions (zero shots). They were
  removed, not left as the default. Restoring the proven capture behavior restored
  exactly the prior crossing hit counts and acquisition times.
- Applying a speed reserve to all crossing approaches also produced zero shots:
  retaining more speed widened the capture turn. The reserve was restricted to
  already-precise tracking of observed turning motion, not general interception.
- The close-parallel and right-angle duel variants exposed additional near passes
  and a collision in intermediate tuning. Early head-on gun victories alone are
  not evidence that prolonged post-merge collision avoidance is solved.

## Verification

Final production tracking results (90 simulated seconds, unlimited-health target):

| Case | Previous hits / shots | Final hits / shots | Final precision time |
| --- | ---: | ---: | ---: |
| Tail chase | 671 / 673 | 671 / 673 | 89.03 s |
| Gentle left turn | 104 / 119 | 569 / 577 | 89.03 s |
| Straight crossing left | 103 / 106 | 103 / 106 | 19.00 s |
| Straight crossing right | 151 / 154 | 151 / 154 | 25.18 s |

Precision time is within one degree and 900 m, excluding startup. Crossing
acquisition remains 70.42 / 64.38 seconds; it did not improve in this pass. The
gentle-turn change converts sustained tracking into more firing opportunities,
not a claim of five times better aim or a general combat win-rate improvement.

Final normal-health duels:

| Start | A hits / shots | B hits / shots | Duration | Minimum center separation | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| 5 vs 3 head-on | 6 / 12 | 14 / 30 | 18.63 s | 430.4 m | Aircraft 5 wins |
| 3 vs 5 head-on | 23 / 28 | 9 / 14 | 19.13 s | 369.1 m | Aircraft 3 wins |
| 5 vs 5 head-on | 7 / 13 | 8 / 13 | 17.80 s | 412.0 m | Team 1 wins |
| 5 behind 3 | 3 / 6 | 0 / 0 | 5.88 s | 376.5 m | Aircraft 5 wins |
| Perpendicular 5 vs 3 | 0 / 0 | 0 / 0 | 240.00 s | 32.6 m | Timeout, both undamaged |
| Close parallel 5 vs 5 | 0 / 0 | 0 / 0 | 46.30 s | 4.2 m | Collision loss, not a gun victory |

The four opening gun exchanges resolve without close contact, unlike the previous
two mixed timeout rounds and same-model collision. The stress cases remain
unresolved: one stalemate and one collision. Initial geometry and these few seeds
do not establish general reliability. Some projectiles remain pending at the
early cutoff and are recorded separately; hits are not inferred from hull damage.

DogfightPursuitSmoketest: 75 checks pass. VisualContactSmoketest: 23 checks pass.
RecoveryRouteCapture, RecoveryTerrainEscape, GoAroundResponse and
DeckFootprintWaveoff (136 checks) pass. No new flight-physics or full carrier-cycle
test was required for the combat-only control changes.

The final source is tested with four 90-second unlimited-health target cases and
six normal-health/ammunition duels. Every run records input hashes and a final
COMPLETE status. The observer now also records first-shot time, minimum center
separation, peak altitude and time spent in tactical resets. These measurements
use debug truth only; they are never fed back into the pilot.

New duel flags:

- `--duel-crossing`: perpendicular paths, each starting 700 m from the crossing.
- `--duel-close-parallel`: co-speed/co-altitude aircraft 50 m apart, deliberately
  inside the hard proximity floor, to exercise separation before gun pursuit.

The existing head-on, swapped, same-model and tail-start modes remain available.
Three seeds were exercised during development; this is not a statistical win-rate
study. A victory at zero shots is explicitly not counted as a gunnery success.

Artifacts live under
`C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier/`:

- `pursuit_acceptance_tracking_{tail_chase,gentle_left,crossing_left,crossing_right}.json`
- `pursuit_acceptance_{merge,swap,equal,tail,crossing,parallel}.log[.json]`
- `pursuit_v3_*`, `pursuit_v4_*`, `pursuit_v5_*`, `pursuit_v6_*` and
  `pursuit_final_*` are intermediate experiments, not final acceptance results.

Headless full-airframe shutdown still emits existing dummy-renderer/resource
cleanup errors after successful tests. Do not confuse these with script/parse
failures, but do not describe the shutdown as clean either.

## Remaining work

The close-parallel collision is an open defect, not a completed safety fix.
Straight crossing acquisition is still slow. Prolonged close maneuvering and
reacquisition after a merge remain harder than the opening gun exchange. The next
investigation should measure achieved separation acceleration and turn curvature,
especially during reversals and visual loss, before increasing the safety bubble
or reintroducing broader tactical maneuvers. No GA or flight-model retuning yet.
