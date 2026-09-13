# Ground-attack early joins

## Scope and implementation

Follow-up to [entry-pose validation](GROUND_ATTACK_ENTRY_POSE_2026-09-10.md).
Retain the planned entry range, height, horizontal capture, real weapon solution
and terrain/pull-out protection. Avoid some of the mandatory outbound staging
when the aircraft can already make a useful join.

While flying to alternate-axis staging, the pilot checks at most once per
second whether the current pose can join the retained line. This shortcut is
enabled for guns and bombs only; rockets retain the prior staging behavior
after the regression described below. The bounded
prediction runs the existing line-capture law for up to 120 half-second steps.
It uses the airframe's load/bank-limited planning radius at at least the existing
110 m/s attack target speed, two-second turn-rate buildup, the existing
cross-track/heading capture thresholds, a low residual turn rate, two seconds
of reserve before the entry and an 8 m/s vertical-transit allowance. Invalid or
vertical-only ground track fails closed.

A successful estimate plus a clear current-to-entry chord starts the existing
line guidance immediately. It does not move the plane, bypass the unified 3D
controller, alter physical forces, authorize a release, or remove the fallback
staging plane. Live line capture and actual-pose terrain/pull-out validation
remain authoritative. A fresh approach resets the check timer.

This is a deliberately approximate reachability estimate, not a full flight
simulation or a swept-terrain proof of the curved join. It does not model wind,
exact bank dynamics or speed loss through the turn. Those uncertainties are
why physical tests and the existing live protection remain necessary.

Diagnostics now record cumulative early-join count and sampled check duration.
The summary tool exposes those plus axis-search duration and still reads old
reports without the new fields.

## Rejected experiment

v17 tested the check on the already selected axis. Both 90-second gun cases
survived and damaged the target on their first pass. Fast-oblique first damage
improved from v16's 62.10 s to 57.55 s; slow-cross stayed near 62.37 s.

v18 also ran the prediction across candidate axes and compared complete join
costs. All four 90-second trials (both gun poses, slow bomb and slow rocket)
survived and made damaging first passes, but none selected an immediate join.
First damage was 57.60, 62.32, 72.42 and 59.80 s respectively. Search cost rose
to 8.74-11.84 ms for guns/bombs and 28.10 ms for rockets under concurrent load.
That candidate-scoring experiment was removed: extra work without a measured
benefit in these cases. The cheap periodic check remains.

v17/v18 were COMPLETE and hash-verified against their source at the time. They
are intermediate evidence, not current-source acceptance runs.

## Intermediate complete matrix: v19

All twelve 150-second paired runs were COMPLETE, hash-verified against their
then-current source and alive, with no GDScript errors and no pending projectile
impacts. However, the alternate fast rocket case made no damaging pass, so this
version was **not accepted unchanged**.

| Case | v16 alternate first damage | v19 alternate first damage | v19 direct first damage | v19 alternate damage |
| --- | ---: | ---: | ---: | ---: |
| Slow crosswise guns | 62.33 s | 62.33 s | 29.62 s | 200.00 |
| Fast oblique guns | 62.10 s | 57.63 s | 50.33 s | 140.00 |
| Slow crosswise bombs | 72.42 s | 72.42 s | 33.83 s | 584.43 |
| Fast oblique bombs | 73.10 s | 63.38 s | 57.10 s | 343.64 |
| Slow crosswise rockets | 59.83 s | 59.78 s | 27.98 s | 559.46 |
| Fast oblique rockets | 62.70 s | None | 48.90 s | 0.00 |

Short joins were actually taken in all three fast-oblique cases and none of
the slow-cross first approaches. Gun/bomb checks sampled at about 0.43-0.47 ms
maximum in this matrix. The original axis search still costs several ms and
up to about 25 ms for rockets under concurrent test load; this iteration does
not solve fleet planning hitches.

The fast bomb's first hit improved by 9.72 s, but it released only one bomb by
150 s versus two in v16. After a terrain emergency on egress, its next direct
approach was terrain-rejected. Earlier first damage is not proof of better
repeat-pass throughput.

The rocket shortcut entered at essentially the same range, height and speed
as v16, but with about 10.2 degrees bank versus 7.0 and 0.46 degrees track error
versus 0.06. Its six impacts missed by 16.0-48.0 m. Predicted miss grew to
roughly 40-54 m during the timed salvo, which continued firing. In v16, several
rockets landed within 4-15 m. This points to burst-precision sensitivity, not a
missing gross approach corridor; it does not establish which small entry
difference caused it. No weapon accuracy gate was changed in response.

The additional natural bomb run (240 s, no injected rejection) also survived
with verified source and no GDScript errors. Its second bomb released at
169.00 s versus v16's 171.33 s. Two bombs, three commits, 558.60 damage; the last
commit did not produce a third release by cutoff. Existing engine interpolation,
camera and shutdown-resource warnings remain.

Artifacts: `ground_v19_join_<slow_cross|fast_oblique>_<guns|bomb|rocket>_<axis|direct>.json`
and `ground_v19_cycle_bomb_axis.json` in normal Godot user data. These now describe
the intermediate pre-guard source, not the final rocket-excluded version.

## Final-source acceptance: v20

The ground-attack smoke suite passes 82 checks, including early-join geometry,
height/range reserve, mirrored turns, degenerate track rejection, real state
handoff to the entry waypoint, timer reset, and the real rocket fallback state.
The only pilot change after v19 is a positive weapon allow-list in the early-
join predictor: guns/bombs retain it; rockets return no shortcut prediction.
No physics, target selection, entry/capture gate or weapon code changed.

All six alternate-axis first-pass cases completed 90 seconds on the guarded
source, alive with source hashes rechecked against current files and no
GDScript errors. All six made damaging first passes, and neither rocket case
took a shortcut. No projectile remained in flight at cutoff.

| Case | First damage | Damage by 90 s | Early joins |
| --- | ---: | ---: | ---: |
| Slow crosswise guns | 62.58 s | 150.00 | 0 |
| Fast oblique guns | 57.58 s | 140.00 | 1 |
| Slow crosswise bombs | 72.42 s | 348.17 | 0 |
| Fast oblique bombs | 63.38 s | 323.75 | 1 |
| Slow crosswise rockets | 59.87 s | 148.67 | 0 |
| Fast oblique rockets | 62.70 s | 95.00 | 0 |

The natural bomb cycle also completed 240 seconds on the final source, alive,
with verified hashes, no GDScript errors and no pending impacts. It reproduced
the two bomb releases at 20.22 and 169.00 s, with 558.60 damage and three commits.
Thus all seven final-source runs survived, and the six first-pass fixtures
retained 6/6 damaging first passes after excluding the rocket shortcut.

Final sampled early-join checks peaked at 0.37-0.49 ms in the eligible first-pass
cases. Axis search peaked at 4.93-6.94 ms for guns/bombs and 14.35-14.66 ms for
rockets in this batch; differing concurrency/load means this is not a claimed
optimization of the original search. All owned test processes have exited.

Final guarded-source regressions also passed: PilotSkill 60 checks,
DogfightPursuit 80, EvasiveFlight 62, BombReleaseSeparation 9,
GoAroundResponse, RecoveryRouteCapture and RecoveryTerrainEscape.

Artifacts: `ground_v20_accept_<slow_cross|fast_oblique>_<guns|bomb|rocket>.json`
and `ground_v20_accept_cycle_bomb.json` in normal Godot user data. v20 uses a
shorter first-pass window than v19, so compare first-hit timing, not 90-second
damage totals against 150-second totals. These are small samples, not a fleet
reliability estimate.

## Limits

The alternate-axis planner remains opt-in. Tests use Aircraft 5, static durable
non-firing targets and the diagnostic ridge. Other aircraft, moving/firing
targets and production terrain/fleet scheduling still require validation.
The goal is useful attacks and survival, not merely shorter plotted routes.

## Next investigation

The six synthetic re-entry pairs deliberately inject a remembered rejection;
their direct controls can still make damaging first passes. A rejection is
currently remembered by target ID, although egress changes the aircraft's
position and the approach direction. Before investing in more elaborate turn
planning, test whether a fresh direct-entry evaluation after egress can avoid
an alternate route that is no longer needed. This is a hypothesis, not an
implemented shortcut: the new direction must still pass entry-pose,
reachability, terrain and recovery checks. Natural blocked-approach scenarios
are more informative for this decision than forced rejection fixtures alone.

Separately, investigate rocket precision across the whole salvo. The pod's
timed burst continues launching after the pilot's initial release decision;
v19 logged later predicted misses well outside a useful hit. Compare continuous
aim control and per-shot usefulness before changing release behavior. Do not
hide this sensitivity by enabling the unproven rocket join or inflating damage.
