# Arrestment stability — 2026-09-08

## Scope

Replace overlapping anti-flip downforces with bounded attitude assistance,
retain moving suspension/collision shapes, and distinguish damaged recoveries
from losses. No carrier geometry or impact-damage thresholds were changed.

The preceding stable-window batch (`random_rtb_20260908_153010_seed_20260908`)
stopped 22/30 aircraft, 21 without recorded damage. Six of its eight failures
had carrier touchdown: four Aircraft 2 cases without a catch, two Aircraft 5
cases after a catch. The other failures were a terrain strike and a timeout.

## Confirmed issues and changes

- LandingGear applied 15,000 N downward per contacted wheel. The cable scene
  separately added two aircraft-weights of downforce. Both now default to zero;
  their explicit overrides remain for diagnostic comparisons. Springs still
  support actual weight, and wheel colliders still move with suspension.
- The cable's signed roll-error calculation already pointed toward deck up,
  but the leveling torque negated that error. An actual free-body physics test
  increased both initial ±10-degree banks to about 21 degrees in 0.5 seconds.
  Correcting the sign reduces them to about 2.2 degrees. Assistance is bounded
  to mass × gravity × 1 m; the leveling term fades below 8 m/s so springs set
  resting attitude. Rate damping remains dissipative.
- Cross-deck centering formerly included the vertical component of hook
  displacement/velocity. It now projects only onto the deck's lateral axis.
  A rotated-deck unit test verifies zero force normal to that deck.
- Removing the downforces alone did not prevent a later pitch-up/tail strike.
  A replay logged bank below 5 degrees but pitch rising from -5.7 to +16.5
  degrees in under a second, without reaching the payout hard stop.
- Arrestment now damps pitch rate using the current world inverse-inertia
  tensor, a 0.25-second response, and a mass × gravity × 3 m torque limit.
  It applies no vertical force and targets no pitch angle. Tests verify that
  torque opposes angular motion at both signs and becomes zero at rest.
- AI post-catch roll uses the same bounded roll-rate capture as final approach
  instead of its old high-gain bank P-controller. The AI actuator-sign inversion
  was already present; this is NOT a second proven roll-sign bug.
- Cable braking/centering remain central forces. The existing payout-limit
  position/velocity correction is not removed, but activations are now counted.
  No new position, orientation, or velocity clamps were introduced.

## Telemetry and harness

Reports include `clean_stop`, `damaged_stop`, `failed`, and
`stopped_damage_unknown`, plus maximum arrestment bank/pitch and payout-limit
correction count. A damaged stop is not a declaration that damage is minor or
repairable: regional health remains available for that assessment.

Arrest samples log rotation, speed, wheel compression, braking/lateral force
and stabilizing torque every 0.2 s. Body-contact traces include attitude.
The runner accepts `-OnlyAircraft` and zero-based `-StartCaseIndex` to replay
selected starts without changing their seed or initial geometry. It retains
the existing selected-input hash checks before/after each model.

## Focused validation

- `ArrestmentLoadSmoketest`: real aircraft rigid bodies, actual gear and body
  colliders, flat test deck, free pitch/roll, pilot/thrust/aero disabled.
  Latest fixture uses authored `TailHook/HookArea`. Cable forces, gear forces,
  rigid contacts and ordinary damage remain active. Clearance samples are
  conservative transformed shape-AABB bounds, not exact mesh distances.
- Initial legacy diagnostics used a proxy hook and five-second observations:
  `arrestment_load_baseline_1788877269.json`. Do not compare their stop counts
  directly with later ten-second authored-hook fixtures.
- The authored-hook 30-case comparison before pitch damping is
  `arrestment_load_current_1788877984.json`: three models, both bank signs,
  separate both/gear-only/cable-only/neither hold variants, plus heavier/faster
  no-hold cases. It exposed the unnecessary suspension bottoming under holds.
- Final configuration: `arrestment_load_current_1788878261.json`, 12 no-hold
  cases. Normal cases: 55 m/s, 2 m/s sink, ±5-degree bank. Stress cases: 65 m/s,
  4 m/s sink, ±8-degree bank, 20% higher gross mass. All stopped, none bottomed,
  none had critical failure. This does not simulate full aerodynamic arrival.
- Roll-sign, rotated-deck lateral projection, and pitch-damper dissipativity
  unit checks pass. LandingDamageTelemetrySmoketest, RandomRTBBatchSmoketest,
  RecoveryDeckEnvelopeSmoketest pass. Collision lookup still passes all 15
  models / 30 configurations / 264 gear and 124 body classifications.
- Focused tests retain shutdown ObjectDB/resource warnings and an existing
  EnemyFighter imported-resource UID fallback warning.

## Targeted flight diagnostics

All report names below have prefix `random_rtb_20260908_` and suffix
`_seed_20260908.json` in Godot userdata. Case numbers are one-based.

| Run time | Aircraft 5 case | Configuration stage | Outcome |
| --- | ---: | --- | --- |
| 162425 | 1 | No holds, corrected cable roll, deck-plane centering | Post-catch tail strike |
| 162742 | 1 | Also bounded AI post-catch roll capture | Damaged stop; 42.53 regional health loss |
| 163058 | 8 | Same physics, added arrest telemetry | Post-catch tail strike; peak pitch 16.49 degrees |
| 163446 | 8 | Also inertia-aware pitch damping | Clean stop; peak pitch 4.73 degrees; zero payout corrections |

These have matched starting geometry, but their approach trajectories/timings
varied even before arrestment. They are not bit-for-bit deterministic flight
replays, so individual outcome differences are not a complete causal A/B proof.
The focused force/torque tests provide the more isolated evidence.

## Fleet comparison

Completed frozen-configuration batch:
`random_rtb_20260908_163635_seed_20260908.json` in Godot userdata.

| Model | Previous stops | Current stops | Clean / damaged stops | Hard / normal touchdowns among stops |
| --- | ---: | ---: | ---: | ---: |
| Aircraft 1 | 10/10 | 10/10 | 10 / 0 | 7 / 3 |
| Aircraft 2 | 5/10 | 7/10 | 7 / 0 | 6 / 1 |
| Aircraft 5 | 7/10 | 10/10 | 10 / 0 | 9 / 1 |
| Total | 22/30 | 27/30 | 27 / 0 | 22 / 5 |

All 27 caught aircraft stopped. There were **zero post-catch losses and zero
payout-limit position/velocity corrections** across the full batch. All 25
tracked inputs stayed unchanged; all eight starting-geometry fields matched
across models and against the previous `153010` batch. No tuning was performed
during the run. This is sample evidence, not a guarantee of universal reliability.

Remaining Aircraft 2 failures, one-based:

- Case 1: missed wire/bolter, then vertical-stabilizer contact with the carrier;
  destroyed without catching a wire.
- Case 6: destroyed in RECOVERY_APPROACH, before PRE_LANDING, at 19 m below
  sampled terrain height. The contact shape/body was not captured by telemetry;
  the transform trace establishes terrain penetration.
- Case 7: carrier fuselage and right-wing contacts, then zero health, without
  a wire catch or separate destruction event.

The maximum reported sink among stops was 6.74 / 7.71 / 5.94 m/s for Aircraft
1 / 2 / 5. Maximum post-catch pitch was 7.74 / 10.10 / 12.31 degrees and bank
11.62 / 9.27 / 4.64 degrees. The damper limits motion; it does not snap aircraft
to a chosen attitude or make every touchdown gentle.

All three engines emitted their complete reports and then crashed at shutdown
(signal 11, exit -1073741819). No SCRIPT ERROR or Parse Error lines were recorded.
Other existing startup/rendering/lifetime warnings are retained in stderr; this
is not an error-free engine run.

Fresh-seed check: `random_rtb_20260908_170144_seed_20260909.json`, three cases
per model, same unchanged physics: Aircraft 1 **3/3 clean**, Aircraft 2 **2/3
clean**, Aircraft 5 **3/3 clean**. Total **8/9 clean stops**. All input hashes and
cross-model starting geometries passed; no script/parse errors, but all three
processes again crashed only after writing complete results at shutdown.

The new Aircraft 2 loss was case 3, after a wave-off and without a catch. Its
transform trace records RECOVERY_APPROACH at 48.5 m below sampled terrain,
several kilometres from the carrier. The last-contact metadata still names an
earlier carrier gear touch; that stale shape identity is NOT evidence that its
gear caused the destruction. Both this loss and main-batch case 6 show a recovery
arc drifting outward with nearly level bank before terrain penetration. That
route-convergence/terrain-clearance behavior is the next concrete diagnostic.

Across the two completed batches: **35 clean stops / 39 attempts; every one of
the 35 wire catches stopped, with zero payout-limit corrections**. Keep the
30-case comparison and nine-case fresh-seed check separate when estimating
reliability; these are small samples and the flight simulation is not bitwise
deterministic.

## Damage and remaining scope

The body-contact damage audit confirms that carrier handling still uses total
relative speed rather than a measured contact-normal impact. That may overstate
glancing scrapes. It was intentionally left unchanged for this physics
comparison: the stop count must not improve merely by weakening damage rules.
Contact-normal/impulse-based damage needs its own instrumented impact tests.
Aircraft 2's uncaught deck contacts and transit terrain strike, and Aircraft 5's
long recovery-route timeout, remain separate approach/escape-guidance issues.
