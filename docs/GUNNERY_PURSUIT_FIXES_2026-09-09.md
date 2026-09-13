# Gunnery pursuit fixes - 2026-09-09

## Outcome

The shared AI now regulates closure, holds a consistent collision escape, applies
the previously discarded rear-target acceleration correction, manages turn energy,
and evaluates shots from the real gun muzzle. Aircraft 5 performs sustained,
accurate straight and crossing pursuit in the new 180-second tests. Gentle-circle
tracking also improves substantially, although late firing remains intermittent.
The two tight-circle cases still produce no shots and remain unresolved.

These are controller and targeting changes, not airframe buffs. This work does not
change aircraft mass, thrust, aerodynamic coefficients, rudder power or gun spread.
The implementation is shared, but these flight acceptance results cover Aircraft 5
only; they are not validation of Aircraft 1 or 2 or of unrestricted combat.

## Implementation

- **Closure throttle:** use range error and target velocity along the sightline to
  approach a roughly 330 m firing position, with speed-acceleration damping. Use
  the airframe's actual stall margin rather than nominal corner speed as the
  minimum pursuit speed. An inside-circle firing position needs lower speed than
  the target. Escapes and energy recovery retain power priority.
- **Consistent collision escape:** latch one deterministic lateral direction for
  at least two seconds and until separation is adequate. Preserve an established
  bank and add climb only near the ground; do not randomize the waypoint each tick.
- **Rear-target guidance:** write the signed behind-target lateral acceleration
  back into the vector consumed by FlightPathFollower. Exact reciprocal headings
  use the established turn sign instead of an unstable angle sign.
- **Energy management:** filter measured acceleration, budget turn load from actual
  stall margin, and unload with full power when speed reserve is exhausted. The
  ordinary turn-response floor and precision aiming no longer fight this recovery.
- **Precision control:** preserve the aircraft's existing airflow trim while
  correcting barrel direction, increase close-in alignment response, and feed
  forward the rudder trim needed to follow a rotating ballistic sightline against
  actual aerodynamic damping. Existing physical actuator limits remain in force.
- **Ballistic correctness:** calculate a fresh bounded solution per AI tick; use
  exact constant-turn target displacement instead of coarse integration. Resolve
  selected guns by category as well as name, obtaining the actual muzzle and
  authored spread. Project the current bore, not the ideal aim direction, and
  prevent the loose geometric fallback from overriding a rejected bore solution.
- **Dispersion confidence:** replace the linear miss-distance score with a bounded
  16-sample estimate of square gun-spread overlap with the target cross-section.
  Independent uniform pitch/yaw spread is how the autocannon samples dispersion.
  This is still an approximate model, not a calibrated combat hit probability.

The trace additionally records steering versus ballistic points, pitch/yaw error,
local angular velocity, actual surface inputs, yaw authority, measured acceleration,
and energy/escape state. High-rate sampling showed the gentle-turn error was a
steady trim error, not an aliased control oscillation.

## Acceptance results

Six independent headless runs, 60 Hz fixed simulation, 180 simulation seconds each,
approximately one second warmup and an additional eight-second projectile drain.
Each uses a fresh production Aircraft 5 and the unchanged 190 dogfight settings
captured by the harness. Targets are invulnerable 4 m-radius spheres at 1000 m;
ammunition is unlimited for measurement. Hits are real projectile collisions.

| Case | Hits / shots | Within 1 degree and 900 m | Longest continuous tracking | Minimum speed |
| --- | ---: | ---: | ---: | ---: |
| Straight tail chase | 1346 / 1348 | 179.02 s | 179.02 s | 77.95 m/s |
| Crossing left | 782 / 791 | 117.97 s | 111.92 s | 58.88 m/s |
| Crossing right | 885 / 898 | 146.95 s | 130.60 s | 58.74 m/s |
| Gentle left circle | 101 / 111 | 179.02 s | 179.02 s | 62.59 m/s |
| Hard left circle | 0 / 0 | 3.98 s | 3.98 s | 52.82 m/s |
| Hard right circle | 0 / 0 | 4.12 s | 4.12 s | 52.82 m/s |

Every run completed with matching before/after input hashes, valid sampled target
motion, target health 100, no invalid-case flag, and one terminal report per shot.
No SCRIPT ERROR, ERROR or FAIL was present in the six run logs. Headless camera
interpolation warnings and ObjectDB shutdown leak warnings remain; this is not
a claim of warning-free cleanup.

Compared with the valid pre-fix 180-second runs:

- Straight chase improved from 73 hits / 143 shots and 14.13 seconds on target to
  1346 / 1348 and 179.02 seconds. Final separation settles near 325 m at 78 m/s.
- Gentle-circle pursuit improved from 0 / 78 and zero time within one degree to
  101 / 111 and 179.02 seconds. Minimum speed improved from about 25 to 63 m/s.
  However, 92 of the 101 hits occurred by 60 seconds: stable sub-degree tracking
  is not equivalent to continuously satisfying the stricter firing gate.
- Crossing cases acquire more slowly, but the longest tracking streaks are 112
  and 131 seconds. Late separation also settles near 325 m.

The hard targets turn at 80 m/s around a 220 m radius (about 20.8 degrees/second),
with no simulated energy cost. The pursuer spends about 40% of sampled time in
energy recovery and ends roughly 0.9-1.0 km away. It remains airborne rather than
falling into the previous deep low-speed condition, but does not establish a
useful firing position. This evidence does not prove that following the target's
circle is physically impossible; it shows the current pursuit/recovery policy
does not solve it. A breakaway/re-intercept tactic is the next focused experiment,
alongside investigating the gentle-circle late firing threshold. Do not loosen
hit gates or increase aircraft power merely to make these metrics pass.

## Artifacts and reproduction

Final JSON traces and stdout/stderr logs are under Godot user data:

`C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier`

Final prefix: `gunnery_acceptance_20260909_151718_`, with case names from the table
(`tail_chase`, `crossing_left`, `crossing_right`, `gentle_left`, `hard_left`,
`hard_right`) followed by `.json`, `.stdout.log`, or `.stderr.log`.

Valid pre-fix comparison prefix: `gunnery_pursuit_validated_20260909_144643_`.
The earlier origin-invalid baseline is excluded, as documented in the diagnosis.
Intermediate `gunnery_fixed_v1` through `v6` runs are development experiments, not
the final acceptance results.

Example PowerShell command from the project root:

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --fixed-fps 60 --quit-after 14000 --path . --scene res://Scenario/GunneryTrackingBaseline.tscn -- --gunnery-duration=180 --gunnery-case=gentle_left --gunnery-output=user://gunnery_gentle_repeat.json
```

## Regression checks

- `Tests/DogfightPursuitSmoketest.tscn`: 62 checks, zero failures. Covers closure,
  deterministic escape/release, reciprocal guidance, energy hysteresis, actual
  barrel versus ideal aim, muzzle/spread lookup, fresh lead, exact circular motion,
  turn-rate feedforward signs/reset, and dispersion-overlap boundaries.
- `Tests/GunneryTrackingBaselineSmoketest.tscn`: PASS; preserves all 190 dogfight
  settings, actual gun spread, invulnerable targets, and correct origin rebasing.
  Its final rerun also emitted tuner-log access warnings and a five-resources-
  still-in-use shutdown error after PASS; those cleanup issues remain unresolved.
- `Tests/RecoveryRouteCaptureSmoketest.gd`: PASS.
- `Tests/RecoveryTerrainEscapeSmoketest.gd`: PASS.
- `Tests/GoAroundResponseSmoketest.gd`: PASS; its sparse fixture still warns about
  the missing approach_4 node.
- `Tests/DeckFootprintWaveoffSmoketest.gd`: PASS, 136 checks.

The four recovery smoke tests were rerun against the final controller. They are
targeted regressions, not a new full landing flight matrix. Runtime cost of the
fresh lead and dispersion calculation has not been profiled at fleet scale.
