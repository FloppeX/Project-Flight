# Ground-attack direct revalidation after egress

## Why

The [short-join tests](GROUND_ATTACK_SHORT_JOIN_2026-09-10.md) improved some first
attacks but left repeat routing inconsistent. A blocked approach is remembered
by target ID. After a real egress changes the aircraft's position, the opt-in
alternate planner previously went straight into a 64-candidate search even if
a direct approach from this new direction was clear.

## Implemented experiment

Before that search, check the new direct direction at the same four candidate
entry heights used by the alternate planner. Each candidate uses the existing
height/speed-derived entry range and the existing weapon-specific corridor
scorer, with an egress waypoint. Both entry and target terrain must be known.

If a candidate clears, retain its height, acquisition range and egress and
hand control to ordinary direct positioning. The normal turn-reachability
extension, heading/bank checks, actual-entry corridor/recovery evaluation,
weapon solutions and emergency pull-out still apply. A nominally clear
corridor is not an assertion that the current aircraft is already aligned or
ready to fire. No physical forces or weapon behavior changed.

If no candidate clears, retain the existing alternate-axis search. This is
only consulted with `ground_attack_alternate_axis_enabled=true`; that parent
feature remains off by default. `ground_attack_direct_revalidation_enabled`
allows a same-source comparison. The diagnostic counterpart is
`--ground-legacy-direct-revalidation`.

Telemetry records accepted revalidation count, last reason and check duration.
The first prototype unit test caught a mismatch between nominal entry height
and flown height; the retained pose fixes that before physical testing.

## Validation

Matched v21 runs hold source fixed and differ only in the revalidation switch.
All use Aircraft 5, real weapons, normal aircraft damage, durable non-firing
targets, collidable ground and the diagnostic ridge, with ordinary headless
timing. No fixed-FPS acceleration or scheduled work is used.

The oblique bomber pair completed 150 seconds, both alive: revalidation first
damage 56.93 s versus 63.38 s, three bomb releases versus one, 508.49 damage
versus 323.75. Releases were at 51.45, 52.18 and 113.23 s versus 58.08 s. This
includes two initial-pass bombs and one on a repeat pass; it is not three
separate passes. Later routing changes with the earlier trajectory, so do not
attribute the whole damage difference to one isolated gate.

All eight physical runs completed with their aircraft alive, positive target
damage, no pending projectile impacts and no GDScript runtime/parse or invalid
call/access errors. Recorded hashes were rechecked against current source.
Pilot and diagnostic sources were held unchanged throughout the comparisons.

| Scenario | Duration | First damage: new / old | Damage: new / old | Releases: new / old |
| --- | ---: | ---: | ---: | ---: |
| Oblique bomb re-entry | 150 s | 56.93 / 63.38 s | 508.49 / 323.75 | 3 / 1 |
| Crosswise gun re-entry | 90 s | 28.72 / 62.32 s | 230.00 / 150.00 | 34 / 45 |
| Oblique rocket re-entry | 90 s | 48.93 / 62.70 s | 123.06 / 178.78 | 6 / 6 |
| Natural bomb wave-off cycle | 240 s | 25.95 / 25.95 s | 545.27 / 558.60 | 2 / 2 |

The natural cycle's second bomb released at 171.00 s with revalidation versus
169.00 s with the old route. Both had three commits but only two releases at
cutoff. This case is slightly slower, not a timing win. Rocket acquisition is
13.77 s earlier, but its salvo deals less damage; faster acquisition is not
evidence of better rocket precision.

Each new case recorded exactly one accepted revalidation and skipped the
alternate search; controls recorded zero. Revalidation cost peaked at
0.05-0.29 ms here, versus 5.84-18.95 ms for control axis searches. These are
small-arena timings under concurrent load, not production-map guarantees.
Work is event-driven: at most four entry-corridor candidates precede the
existing search when all fail, rather than adding a per-frame search.

The focused suite passes 104 checks, including retained height/range, valid
and blocked entries for all three weapons, unknown/degenerate geometry, the
comparison switch, rejection consumption without an automatic commit, and
normal turn-space extension after revalidation. A test-file indentation error
introduced while extending coverage was corrected before this final pass.
Skill (60), pursuit (80), evasion (62), bomb separation (9), go-around response,
recovery route capture and recovery terrain escape regressions all passed.
Existing engine interpolation/camera and shutdown-resource warnings remain.

Artifacts in normal Godot user data:

- `ground_v21_revalidate_bomb_{fast|cycle}_{new|old}.json`
- `ground_v21_revalidate_guns_slow_{new|old}.json`
- `ground_v21_revalidate_rocket_fast_{new|old}.json`
- `ground_v21_GroundAttackPlanSmoketest_retry.log` and the other v21 smoke logs.

All owned test processes have exited. No automation was created or resumed.

## Limits and next step

These small fixed-arena comparisons cannot establish fleet reliability or
production-terrain performance. The direct corridor is nominal: direct
positioning can change its bearing while turning, so the live actual-pose
checks remain essential. Existing corridor samplers can skip unavailable
interior terrain samples; checking known endpoints is not a full terrain-data
coverage proof. Do not enable globally on this evidence alone.

Rocket salvo precision is still a separate unresolved issue. Shortening an
alternate-axis join remains disabled for rockets after the v19 regression;
revalidation instead uses the existing normal direct controller. No timed-burst
behavior or accuracy threshold has been weakened to improve these results.

Keep this revalidation within the opt-in planner, but do not treat it as a
blanket routing win. Next, investigate useful aim throughout the rocket salvo
and broaden the natural re-attack scenarios. Include genuinely blocked new
directions, other airframes and production terrain before enabling the parent
planner generally.
