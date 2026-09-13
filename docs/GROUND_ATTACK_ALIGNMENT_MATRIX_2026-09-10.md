# Broader ground-attack alignment comparison

## Test design

Twelve Aircraft 5 runs compare the existing production direct re-entry with the
opt-in alternate-axis planner. Each of bombs, rockets and guns is tested in both
starting poses, with both planner modes:

| Pose | Position (m) | Heading | Initial speed |
| --- | --- | ---: | ---: |
| Slow crosswise | (1000, 500, -1800) | 90 degrees | 85 m/s |
| Fast oblique | (-1000, 500, -1800) | 225 degrees | 125 m/s |

Heading zero points along +Z; positive headings rotate toward +X. The remembered
terrain rejection is set at startup so alternate-axis cases actually exercise
that planner. This is a controlled re-entry reproduction, not a mission-start
test. Each case runs for 150 simulated seconds, with real flight controls,
physical colliders, normal aircraft damage, and the existing terrain protections.
The two stationary targets retain unlimited health and do not fire back.

The physical ridge is 260 m high, spanning X [-1500, 1500], Z [600, 1000]. Four
headless processes run concurrently, using ordinary timing and `--max-fps 60`,
never `--fixed-fps`. Results are only accepted when COMPLETE, source hashes match,
and no GDScript runtime/parse or invalid-call/access errors are present. Bombs or
rockets still in flight at cutoff are explicitly counted as pending, not hits or
misses. Startup and wall-clock-sensitive weapon timing mean these comparisons
are not perfectly deterministic.

## Measurements and decision

The harness now accepts explicit heading and speed, records the actual initial
pose, time to first target damage, every release time, and per-commit axis error,
bank and speed. Existing traces retain terrain intervention, end reasons and
projectile impacts. The question is whether alignment produces useful attacks
without introducing avoidable crashes or prolonged non-committing maneuvers;
attack-state entry alone is not success.

Reproduce with `tools/run_ground_attack_alignment_matrix.ps1`; summarize with
`tools/summarize_ground_attack_alignment.ps1 -RunTag ground_v14_align`.
The alternate planner remains disabled by default during the comparison.

## Results

All twelve `ground_v14_align_*` runs are COMPLETE at 150 simulated seconds,
with every aircraft alive at the cutoff. Every recorded source hash matches
current source, and no GDScript runtime/parse or invalid-call/access errors were
found in their stderr logs. The runner finished with `completed=12 invalid=0`.
No test process remains active. No scheduled task was created or resumed.

**Decision: do not enable the alternate planner globally.** Direct re-entry
produced a damaging first pass in 6/6 cases; the alternate planner did so in 2/6.
In each of the four failed alternate first passes, no weapon was released before
the second commit. The alternate fast-gun case never fired at all in 150 seconds.
All six alternate cases genuinely exercised line guidance and recorded a valid
axis capture at their first commit, so this is not an unexercised feature test.

| Pose / weapon | First damage: direct | First damage: alternate | Total damage: direct | Total damage: alternate |
| --- | ---: | ---: | ---: | ---: |
| Slow crosswise / guns | 29.63 s | 94.68 s | 420.00 | 30.00 |
| Slow crosswise / bombs | 33.83 s | 102.23 s | 634.62 | 323.12 |
| Slow crosswise / rockets | 27.90 s | 95.53 s | 145.00 | 157.13 |
| Fast oblique / guns | 50.78 s | No damage | 110.00 | 0.00 |
| Fast oblique / bombs | 57.10 s | 48.88 s | 598.71 | 716.73 |
| Fast oblique / rockets | 48.90 s | 41.75 s | 270.46 | 292.93 |

These are single paired samples per pose/weapon, not reliable population rates.
Compare damage within a weapon pair; pooling damage across weapon types would
give a misleading score. The slow rocket alternate case eventually deals
slightly more damage, but loses almost 68 seconds before the first damaging
attack. Commit counts alone are also misleading: fast alternate guns enter
ATTACK_DIVE twice while producing no shots.

All tracked bombs and rockets had completed impact records by the cutoff; none
were left pending. The eight gun/bomb tests each took about 150.2 wall seconds.
Rocket wall times were 305.98/304.50 s for slow alternate/direct, and
315.61/322.62 s for fast alternate/direct. Existing engine camera/interpolation
and resource-cleanup warnings remain; these are not clean-shutdown claims.

Artifacts are in the normal Godot `Land Carrier` user-data folder, named
`ground_v14_align_<slow_cross|fast_oblique>_<guns|bomb|rocket>_<axis|direct>.json`,
with matching stdout/stderr logs. The 10-second `ground_v14_harness_smoke.json`
validated the new input options but is not included in the twelve physical
comparisons.

## What the broader cases exposed

The lateral capture itself occurs: all completed alternate cases have a recorded
axis capture at their first commit. The problem is the pose at which that capture
finishes. A fixed heading/cross-track test does not ensure enough remaining
distance to establish the weapon's dive and aim before pull-out.

| First attack entry | Time | Height | Horizontal range | Speed |
| --- | ---: | ---: | ---: | ---: |
| Slow guns, alternate | 29.97 s | 545.1 m | 875.0 m | 100.1 m/s |
| Slow guns, direct | 21.73 s | 372.3 m | 1,398.2 m | 96.9 m/s |
| Slow bombs, alternate | 29.03 s | 416.0 m | 904.0 m | 100.7 m/s |
| Slow bombs, direct | 20.37 s | 459.5 m | 1,397.5 m | 91.3 m/s |
| Slow rockets, alternate | 32.27 s | 345.6 m | 882.6 m | 101.9 m/s |
| Slow rockets, direct | 21.93 s | 368.4 m | 1,395.7 m | 97.2 m/s |
| Fast guns, alternate | 33.00 s | 573.4 m | 1,031.8 m | 99.8 m/s |
| Fast guns, direct | 43.87 s | 309.2 m | 1,396.6 m | 109.0 m/s |
| Fast bombs, alternate | 36.07 s | 464.7 m | 1,383.1 m | 100.3 m/s |
| Fast bombs, direct | 44.67 s | 399.8 m | 1,398.2 m | 105.1 m/s |
| Fast rockets, alternate | 35.23 s | 394.0 m | 1,395.7 m | 102.5 m/s |
| Fast rockets, direct | 43.90 s | 305.6 m | 1,394.8 m | 109.2 m/s |

For example, the slow gun alternate entry has only 79.2 m cross-track and 8.35
degrees track-heading error, but its height/range corresponds to a 31.9-degree
line down to the target, versus 14.9 degrees for direct re-entry. These are
geometric angles, not measured flight-path angles. It enters ATTACK_DIVE and
then physically pulls out without firing. Its first damage comes on a later
direct pass at 94.68 s, versus 29.63 s for the baseline. Fast guns likewise make
two attack entries without firing any rounds in 150 s.

The fast bomb case is a useful contrast: alternate capture completes near
1,400 m and produces an earlier damaging attack. This supports the remaining-
distance explanation, although it is not a controlled isolation of every
vertical-control or weapon-aiming effect.

Fast rockets likewise finish alternate capture near 1,400 m and deal first
damage earlier. In contrast, all three slow alternate entries finish around
875-904 m and fail to damage the target until a later pass.

The current search validates hypothetical entry points at 1,400 m, but its
fixed `commit_range + 2 * turn_radius` staging offset does not ensure the real
aircraft is ready there. Its two candidate heights and held staging altitude
also do not describe a complete descending attack setup. The existing live
terrain/recovery checks correctly remain authoritative; loosening them would
not solve the missed aiming window.

One separate diagnostic caveat: the slow direct rocket run has a projectile
collision only 0.09 s after release, about 1,012 m from the target, against a
generically named rigid body. Its other five impacts miss by about 8-16 m. This
suggests a near-launch collision, but the current body-name-only impact record
does not establish what it hit. Do not treat that run's mean miss as a pure
aiming/alignment measurement; richer impact-body identity is a useful follow-up.

## Next implementation slice

1. Plan a usable entry pose: range, altitude, heading and speed, with time for
   weapon aiming and the existing physical pull-out margin. Keep transit
   clearance and terminal attack altitude distinct.
2. Start the turn and line capture early enough to reach that pose, using the
   aircraft's actual speed/turn response plus roll-out and lateral-settling
   distance. Preserve line guidance during the planned descent. Do not merely
   restore a hard 1,400 m abort gate: the earlier iteration already showed that
   an extra gate alone creates needless wave-offs.
3. First re-test the two failing gun poses and slow bomb/rocket entry. Then
   repeat this full matrix, evaluating first damage and complete useful passes,
   not just commit counts. Keep the current production direct planner until the
   candidate stops sacrificing those passes.

Moving/firing targets, Aircraft 1/2 and production terrain remain a separate
validation stage. No production-control behavior was changed during this matrix.

Follow-up: the [entry-pose implementation and v16 results](GROUND_ATTACK_ENTRY_POSE_2026-09-10.md)
recover all six damaging first passes, but retain an excessive setup-time cost.
The next step is a shorter feasible join while preserving the usable entry pose.
