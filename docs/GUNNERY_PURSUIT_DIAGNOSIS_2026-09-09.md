# Sustained pursuit and gunnery diagnosis

Historical diagnosis: the fixes and subsequent acceptance results are recorded in
[Gunnery pursuit fixes](GUNNERY_PURSUIT_FIXES_2026-09-09.md). The unchanged-production
statement below applies to this diagnostic stage, not the current working tree.

## Scope

Diagnostic follow-up for Aircraft 5. Production AI, aerodynamics, engine settings,
weapon spread and firing rules are unchanged. Only the opt-in measurement
harness, its smoke test, an isolated guidance probe and documentation were edited.

## Test validity correction

The first long baseline omitted origin-rebasing of cached scripted target paths.
`FloatingOrigin` is an enabled autoload in the current project and recentres
around the active camera at 4 km. It translated both bodies, but the next
`GunneryGym._update_target()` restored the target to its old absolute path.
The new velocity/position trace exposed roughly 4 km range discontinuities.
Those are not evidence that the pilot flew away from its target.

The baseline harness now registers for origin shifts and rebases both straight
and circular paths and the observer's previous target position. A first rerun
then exposed a second artifact: kinematic freeze computed a one-frame target
velocity of approximately -240,000 m/s from a coordinate rebase, despite the
target actually continuing at 78 m/s. The scripted target now uses static freeze
and supplies its analytical velocity, preserving real bullet collision checks.
Sampled displacement velocity is checked against reported velocity; errors above
1 m/s invalidate the case. Target health remains unlimited.

Verification: the baseline smoke test preserves all 185 dogfight settings,
authored 0.35-degree spread and unlimited target health. Added checks cover
rebasing both path types and previous observation, and preserving reported
target velocity after a coordinate rebase. Smoke passes; shutdown resource-leak
warnings/errors remain cleanup issues and are not claimed as a clean shutdown.

Excluded diagnostic runs (preserved in user data):

- `gunnery_pursuit_20260909_143944_*`: exposed target path discontinuities.
- `gunnery_pursuit_rebased_20260909_144324_*`: position correction only; tail
  case still had a one-frame kinematic-velocity spike. Not a clean baseline.

The legacy optimizer's base `GunneryGym` has not been repaired here. These
corrections are in the opt-in baseline subclass; do not infer that a legacy GA
run is now origin-safe.

## Validated replacement runs

`user://gunnery_pursuit_validated_20260909_144643_tail_chase.json` and
`user://gunnery_pursuit_validated_20260909_144643_gentle_left.json`, with paired
stdout/stderr files, both COMPLETE. Each ran 180 simulated seconds at 60 Hz,
with an additional 8-second projectile drain. Both targets remained at 100/100
health. All 221 physical shots generated reports. Selected source hashes stayed
unchanged. No script/runtime errors appeared in the completed flight logs;
interpolation and ObjectDB exit warnings were present. No test remains running.

| Case | Hits / shots | On target total / longest | Origin shifts | Maximum sampled target velocity error |
| --- | ---: | ---: | ---: | ---: |
| Tail chase | 73 / 143 | 14.13 s / 7.70 s | 3 | 0.0118 m/s |
| Gentle left turn | 0 / 78 | 0 s / 0 s | 1 | 0.0032 m/s |

On target means within 1 degree of a fresh ballistic solution and within 900 m.
These are individual diagnostic runs, not statistically reliable success rates.
Startup/runtime scheduling and random maneuver decisions can affect exact
counts; do not treat different totals between probes as a tuning improvement.

### Straight chase

The sampled range stayed below 576 m after the coordinate corrections. The
aircraft does regain contact: the earlier claim that it simply opens to many
kilometres is withdrawn. At 21.08 s it is approximately 172 m behind, still
closing at 12.2 m/s with full engine power. Reconstructing the unchanged
collision predictor from sampled relative position/velocity first triggers
at about 21.78 s and 164 m. This is an observation-time reconstruction, not an
extra call to the randomized avoidance function.

It then breaks/climbs and slows: at 31.08 s, speed is 71.2 m/s and aim error
57.6 degrees. It reacquires around 71 s and 141 s but repeats close-pass escapes.
All 73 hits had arrived by 31.08 s; subsequent firing added no hits. Full
throttle demand remained 1.0 in all recorded samples.

### Gentle turn

The target turns at 84 / 480 = 0.175 rad/s, approximately 10.0 degrees/s.
At 11.08 s the pursuer briefly matches that track rate (10.6 degrees/s), with
61.3-degree actual bank versus 62.5 commanded. It is closing at 31.9 m/s.
This is not simply an inability to roll to the commanded bank.

While firing early, current-bore projected misses are approximately 11–15 m
at 399–513 m range, with roughly 1.7-degree aiming error. The fire heuristic
can report `ready` and an ideal-aim miss below 3 m for those same samples.
The physical result is 0 hits from 78 shots.

Speed falls from 89.1 m/s at 11 s to 62.9 m/s at 21 s. The pursuer remains near
64 m/s for a while, accumulating heading error, and later reaches 25.3 m/s.
The sampled collision predictor does not trigger in this case. Full power
does not prevent the sustained pursuit from losing energy. This identifies
energy/trajectory management as a problem; it does not yet isolate how much is
caused by the precision-controller transition, induced drag or vertical maneuvers.

## Confirmed code-level findings

### No closure-speed regulation in dogfight

`AIPilot._state_dogfight()` sets throttle to 1.0 unless a tactic overrides it.
The corner/rejoin `target_speed` assignment is not a throttle servo in this
execution path. `_apply_controls()` passes the throttle directly to ControlEngine;
the ground-attack energy-recovery overlay does not handle DOGFIGHT.
This can bring a faster pursuer into the collision-avoidance envelope instead
of matching speed at a useful firing separation. It does not explain every
failure to close: loaded turns can instead lose too much speed at full power.

### Reciprocal-target turn correction is discarded

`FlightPathFollower.solve_velocity_guidance()` calculates a stronger signed
lateral acceleration for targets behind the actual flight path. However, that
modified scalar is never written back into `requested_accel_world` before
`solve_acceleration_guidance()` recomputes the lateral acceleration from that
unchanged vector. Thus the intended reciprocal-target correction has no effect.

Read-only reproduction:
`Tests/PursuitGuidanceDiagnostic.gd`, speed 100 m/s, response time 2 seconds,
80-degree bank envelope, no feed-forward acceleration:

| Target bearing | Returned bank magnitude |
| --- | ---: |
| 90 degrees | 78.91 degrees |
| 150 degrees | 68.59 degrees |
| 179.9 degrees | 0.51 degrees |
| 180 degrees | 0.000585 degrees |

The isolated probe reports current behavior, not a PASS that this is correct.
This confirms a genuine defect, but does not quantify how often it occurs in
unrestricted combat. Shared guidance changes need non-combat regression tests.

### Collision escape direction is re-randomized every frame

The dogfight state calls `_compute_dogfight_collision_avoidance()` each tick.
When it detects danger, `_build_dogfight_collision_avoid_waypoint()` rolls new
random lateral and vertical choices; there is no persistent escape waypoint or
latched side in this path. Precision aim is disabled during avoidance. A nominal
3-second closest-approach check and 130 m separation can trigger before actual
contact, even in a same-direction chase. Throttle regulation should prevent
unnecessary entries; a real escape needs a stable direction and exit hysteresis.

### Fire confidence does not project the actual gun direction

`_dogfight_has_good_fire_solution()` does check a muzzle-versus-aim angular gate,
but its predicted impact and hit-chance heuristic use the ideal `aim_dir`, not
`muzzle_forward`. Passing that loose angular gate is not equivalent to the
current barrel intersecting a small target. The baseline's current-bore miss
and actual physical bullet reports are independent checks, not that heuristic.
The declared hit chance is not a calibrated probability.

## Recommended implementation order

1. Repair the discarded reciprocal-turn correction; add left/right and near-rear
   regression cases, including preservation of forward-target behavior.
2. Add range/relative-speed regulation with a usable firing stand-off and a
   stall/energy floor. Latch a collision-escape maneuver until safely clear.
3. Check current-bore projectile paths for firing confidence, and investigate
   any persistent lead-tracking error. Tightening the trigger alone only reduces
   wasted shots; it will not improve the steering.
4. Use measured speed loss, bank, load and actual turn rate to add energy-aware
   pursuit: recover speed or change interception geometry instead of endlessly
   tightening a turn the aircraft cannot sustain. Do not start by raising gains
   or reducing aircraft mass/drag.
5. Repeat these same long invulnerable-target cases, then left/right crossings
   and harder turns. Extend to Aircraft 1 and 2 after shared behavior is credible.
   Regression-check recovery because the flight-path follower is shared.

No production fixes or genetic optimization have been applied in this diagnosis.
