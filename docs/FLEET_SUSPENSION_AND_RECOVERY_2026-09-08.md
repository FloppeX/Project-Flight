# Fleet suspension and recovery follow-up — 2026-09-08

Follow-up: [arrestment stability](ARRESTMENT_STABILITY_2026-09-08.md) replaces
the stacked hold forces and records a later 27/30 clean-stop batch.

Suspension-only validation status: the resumed, unchanged-input 30-flight batch is complete at
**22/30 stops**, down from the previous 27/30. The fleet collider/drop checks
pass, but this is not a flight-reliability improvement. See the completed-run
section below for damage, failures, and infrastructure caveats.

## Scope and findings

All 15 flyable scene configurations were checked (Aircraft 1–12, 14,
CompleteFighterJet, EnemyFighter). Aircraft 13/15 do not exist. Helicopters
already enabled collider travel; several older fixed-wing scenes inherited
disabled movement and 12,000 N/m springs. Aircraft 5's 30,000 N/m value came
from a later suspension pass, not a consistent fleet load-sizing rule.

Scene masses are base masses. Spawned stores increase them: this fixture loads
Aircraft 1/2/5 at 920/1,700/1,400 kg. The earlier discussion's 720/1,200/900 kg
figures were scene values, not necessarily live gross weights.

## Changes

- Shared LandingGear defaults to moving collision shapes. No aircraft overrides
  it off. Existing retractable gear and locked helicopter skids retain their
  deployment behavior and safe-wheel collision classification.
- Spring strength has a static-load minimum: the most-loaded wheel uses no more
  than 35% of available stroke at the sizing mass. Authored stronger springs are
  retained. Damping has a corresponding critical-damping minimum for that wheel.
  Rechecking on mass change can increase capacity; it does not soften springs
  again after stores are released. Two-skid aircraft use equal left/right loads,
  not the three-wheel fore/aft formula. Four-wheel load sharing remains an equal-
  load approximation; the calculation is not a full flexible-undercarriage model.
- Wheel collision geometry responds immediately to compression, with a small
  contact skin and integration/synchronization lead, while rebound remains
  smoothed. The rigid shape remains a stop at the configured travel limit.
- Suspension rays start above the unloaded wheel origin, using signed distance,
  so contact is not lost when that origin goes below the deck during compression.
- Dampers use wheel-point velocity relative to the contacted surface, including
  rotation around the centres of mass. Helicopter deck matching applies only
  horizontal force, instead of assigning a complete velocity vector that can
  overwrite vertical suspension integration.
- First spring-supported contact publishes the existing aircraft landing event
  and severity/damage rules, even without a rigid tire-impact callback. Frozen
  deck placement does not publish a landing. Damage thresholds are not relaxed.
  Contact can now be sampled before the rigid solver slows the aircraft, so
  touchdown-severity counts are not a strictly identical measurement to older logs.
- Aircraft 2 rudder power: 1.8 → 2.4. General angular damping is unchanged.
- The previous final-descent guidance and finite-stern floor are retained.
  An experimental anticipatory 3.5 m/s touchdown sink cue was removed after
  the flight comparison described below; its helper and unit checks were removed too.
- Below 20 m above deck, bolter energy recovery cannot command zero climb merely
  because airspeed is low: a bounded speed-aware climb cue takes priority.
  Bolter roll levelling uses the existing physical roll-response controller.
  This is not yet a full wing/tail swept-obstacle planner.

## Validation

- FleetSuspensionSmoketest: 15 configurations; every gear collider physically
  moves and remains registered as safe; static travel is within its budget.
- 60 isolated vertical drops: all 15 configurations, at initial descent speeds
  2/4/6/8 m/s. Pilot, thrust, aerodynamic lift, arrestor
  and rotation are disabled for this fixture; ordinary gravity, collision and
  suspension/damage rules remain. Initial position clears both tires and spring
  probes. These are suspension fixtures, not free-attitude landing trials.
- Final drop report: `fleet_suspension_current_1788870060.json` in Godot userdata.
  All drops produced touchdown telemetry and settled without destruction or
  recorded regional damage. All 2 m/s drops retained travel. Several 6–8 m/s
  drops bottomed out; Aircraft 1/5 also had substantial high-speed rigid-contact
  rebound. PASS does **not** mean these hard impacts are acceptable landings.
  All 60 drops settled to less than 0.05 m/s vertical speed; 12 bottomed out.
  The final configuration check also verifies PhysicsServer shape transforms,
  not merely the visible scene-node positions.
- Existing landing_gear_strut_smoketest passes, including Aircraft 5's loaded
  deck stance, lower-leg hierarchy, and no upward pop on physics activation.
- Collision classification regression passes: 15 models, 30 configurations,
  264 safe-gear contacts and 124 body contacts.
- RecoveryDeckEnvelopeSmoketest, RandomRTBBatchSmoketest and
  LandingRecoveryReliabilitySmoketest pass.

Initial diagnostic drop runs had incomplete assertions and an initial-velocity
setup issue; they are not before/after evidence. The optional legacy-settings
fixture is only a configuration comparison on the current solver, not historical
physics. The first flight diagnostic `random_rtb_20260908_140535_seed_20260908`
was stopped before completion to add compliant-touchdown reporting. It is not
pooled into fleet results.

### Rejected descent-braking experiment

`random_rtb_20260908_141101_seed_20260908` completed Aircraft 2 at 5/10 stops
and five crashes, versus the previous 8/10 stops. Aircraft 1 was stopped before
completion; this is not a 30-case result. Successful cases were 1, 2, 4, 5, 9.
Case 3 hit terrain after a wave-off; other losses included carrier-body strikes
during missed approaches. Traces showed some approaches flattening with the
hook still about six metres above the remaining wires. Gentler contact without
arrestment was not accepted as an improvement. The height-only sink-braking cue
was therefore removed before the next batch. Its input hashes were checked
against the saved snapshot before reverting it.

The first retained-version attempt, `random_rtb_20260908_142343_seed_20260908`,
ended unexpectedly during Aircraft 2's fourth case, exit -1, without a final
report or a logged script error/crash trace. Its three completed cases (two stops,
one carrier-contact loss) are partial evidence only. No controller changes were
made between this interrupted attempt and its restart.

### Earlier validation interrupted by changing shared scene

The restart, `random_rtb_20260908_143206_seed_20260908`, used identical hashes
for all 11 saved task inputs, but picked up concurrent changes outside that
snapshot. `LandCarrier2.tscn` was saved at 14:32:04, immediately before the
14:32:06 restart; `MonitorStation.gd` was also being changed during this task.
Repeated `CarrierTargetCamera._should_render_feed` errors at line 319 called
the nonexistent `MeshInstance3D.is_on_screen()` method. These files were not
edited or reverted by this suspension task.

The restart's first Aircraft 2 case crashed and its second stopped, whereas the
earlier retained-version process stopped in both. That does not establish which
change caused the outcome difference. The new camera error also does not prove
why the earlier process exited. The current process was deliberately stopped
to avoid presenting a mixed, changing-scene run as controlled validation.

At that point there was no completed 30-case flight result for the retained changes. The
completed 60-drop fleet tests and focused regressions remain the verified result.
The failed sink-braking experiment is retained as diagnostic evidence, not a
reliability estimate for the current code. The previous 27/30 result must not be
attributed to this new suspension configuration.

### Completed stable-window batch

After the user paused the other scene work, the camera frustum-gate fix was
already present and was preserved. CarrierTargetCameraSmoketest and
RandomRTBBatchSmoketest passed before the run. No flight, gear, or scene tuning
was performed during this batch.

Command: `tools/run_random_rtb_batch.ps1 -FirstAircraft Aircraft_2 -CasesPerModel 10 -Seed 20260908`.
Report: `random_rtb_20260908_153010_seed_20260908.json` in Godot userdata.
The runner now snapshots/hashes 25 selected inputs, including carrier scene,
collision setup, camera, terrain and scenario scripts; the carrier GLB is hashed
without copying its binary. Hashes are checked before and after each model.
All checks passed. This is a selected-input manifest, not a complete isolated
copy of every runtime dependency.

All 30 initial geometries match across models and against the previous
`125430` batch (eight entry fields, tolerance 0.001). Carrier scene changes
between those historical runs mean this is not a one-variable causal A/B test.

| Model | Previous stops | Current stops | Stops without recorded damage | Hard / normal among stops | Mean time to stop |
| --- | ---: | ---: | ---: | ---: | ---: |
| Aircraft 1 | 10/10 | 10/10 | 10/10 | 6 / 4 | 229.5 s |
| Aircraft 2 | 8/10 | 5/10 | 4/10 | 5 / 0 | 304.2 s |
| Aircraft 5 | 9/10 | 7/10 | 7/10 | 7 / 0 | 222.0 s |
| Total | 27/30 | 22/30 | 21/30 | 18 / 4 | — |

Success still means a wire catch followed by two seconds continuously below
the stop-speed threshold, not a full stow cycle. Regional damage was observed
for every case. Normal/hard classifications are affected by earlier spring
contact reporting and must not be compared as identical measurements to old
rigid-contact-only telemetry. Maximum reported sink among stops was 7.53, 6.78,
and 8.88 m/s for Aircraft 1, 2, and 5 respectively.

Failure and damage details (one-based cases):

- Aircraft 1: all ten stopped without body-contact signals or recorded damage;
  no wave-offs or bolters. This validates these starts, not arbitrary player landings.
- Aircraft 2: stops in 1, 2, 3, 4, 9. Case 3 lost 53.49 fuselage-part health
  despite the legacy main health staying at 150. Case 5 had fuselage/wing
  contacts and ended at zero health without a destruction event. Case 6 struck
  terrain in RECOVERY_APPROACH before reaching PRE_LANDING. Cases 7/8/10 were
  destroyed on left-wing/right-wing/vertical-stabilizer carrier contacts. There
  were seven wave-offs and one bolter across this model's ten cases.
- Aircraft 5: stops in 2, 3, 4, 5, 6, 7, 9, all without recorded damage.
  Cases 1 and 8 **caught a wire but failed before a stable stop**, with fuselage
  and right-wing carrier contacts respectively; both ended at zero main health
  and 50 part-health loss, without a separate destruction event. Case 10 remained
  alive but timed out at 900 s, only reaching PRE_LANDING at 864.9 active seconds.

Infrastructure remains imperfect: all three processes wrote their complete
results, then crashed with signal 11 / exit -1073741819 during shutdown. There
were no SCRIPT ERROR / Parse Error lines, but there were tactical-screen
add_child startup errors, material/RID cleanup errors, interpolation warnings,
and four freed-lambda-capture errors in Aircraft 2. These are retained as
infrastructure warnings; this was not an error-free engine run. Their impact on
individual flight outcomes has not been established.

### Evidence-led next step

The existing arrestment hold applies **15,000 N downward at each wheel** whenever
the cable is engaged. Spring sizing covers static aircraft weight, not this
additional load, and spring compression is clamped to maximum travel. A
30,000 N/m spring over 0.4 m produces only 12,000 N at full travel before damping;
15,000 N of hold alone exceeds that, even before the wheel's share of weight.
Actual auto-sized stiffness depends on gross mass, so inspect live per-wheel
force margins rather than assuming every aircraft has that exact capacity.

This is a concrete force-budget mismatch and a plausible contributor to the
post-catch body strikes, **not yet proof of their complete cause**. The 60-drop
fixture disabled arrestor forces and rotation, so its PASS did not exercise it.

Next, add a free-pitch/roll arrestment fixture with wheel compression, spring
force, hold force, body clearance and contact identity telemetry. Compare current
hold with a load/travel-aware bounded hold, preserving moving colliders and real
body damage; replay Aircraft 5 cases 1/8 and Aircraft 2 case 3 before another fleet
run. Separately isolate Aircraft 2's yaw increase from transit/escape guidance
using paired runs, and address the terrain strike and Aircraft 5 case-10 route
timeout. Do not reintroduce the rejected height-only sink clamp or assume softer
touchdowns alone will prevent these failures. No speculative fix to the hold
force was applied during this validation run.
