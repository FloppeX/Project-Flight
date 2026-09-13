# Aircraft_5 coordinated landing inputs

## Outcome

The PRE_LANDING rudder cutoff is fixed. Validation produced **3/4 complete deploy/launch/return/catch/stop/stow cycles**, with no damage on the three stored aircraft, and **6/6 unassisted stopped catches** in the prepared turn-in matrix. This is progress, not an all-conditions reliability claim.

## Implementation

- Keep the acceleration-guidance branch's single roll-command owner.
- Replace its unconditional zero rudder with a bounded heading-rate command derived from the same requested lateral acceleration. Feedback uses measured flight-path turn rate, body heading rate and signed sideslip. The old waypoint rudder command is not mixed back in.
- Preserve the incoming rudder smoothing state before the route controller runs, so the route update cannot dilute the terminal command. Smooth over a 0.15 s time constant and limit output to ±0.7.
- Observe carrier-relative centre-of-mass acceleration from successive velocity samples, filtered over 0.25 s and bounded against derivative spikes. Reset the observer when the landing picture becomes invalid.
- Use that measured acceleration, rather than nominal `g*tan(bank)`, during the predictor's response-delay interval. The rest of the bounded terminal forecast remains approximate; it is not a guarantee of reachability.
- Leave FINAL's existing bank/yaw mixing, pitch/throttle laws, hook geometry, cable spacing and landing gates unchanged. FINAL does receive the improved acceleration estimate in its sight forecast.

The changed control branch is guarded by `landing_sight_acceleration_guidance_enabled`, currently enabled only on Aircraft_5. Aircraft_1/2 were not retuned. Commands still go through the ordinary aerodynamic controls; no aircraft transform, velocity or arrest force is imposed by the new controller.

The previous full-cycle failure showed bank near the requested 22.2° with zero rudder and very little lateral acceleration. After this fix, representative PRE_LANDING samples request rudder around -0.2 to -0.35 and measure lateral acceleration around -2 to -3 m/s². That is materially closer to the requested -4 m/s², though not exact tracking.

## Logged runs

All files are under `C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier`.

| Run ID | Test | Result |
| --- | --- | --- |
| `desert_recovery_20260908_024743_seed_20260908` | One Aircraft_5, normal return route and managed storage | PASS: one go-around, then caught at 410.2 s, stopped at 418.0 s, stored at 451.7 s. Health 100, damage 0. |
| `desert_recovery_20260908_025120_seed_20260908` | Three Aircraft_5s sharing the deck queue | FAIL overall: two stored healthy at 440.7/606.6 s; the remaining aircraft was destroyed at 950.5 s. No replacements. |
| `landing_turn_in_matrix_20260908_025131` | Left/right entries at 50/60/70 m/s | Six caught and continuously below 1.5 m/s for two seconds, no recovery assistance, health 100 and damage 0. No bolters, wave-offs, crashes or arrest failures. |

The full-cycle reports are named `carrier_combat_test_<run ID>.log`; each run also has `<run ID>.stdout.log` and `.stderr.log`. The matrix additionally has `.json` and `.report.log` results.

These are different entry/traffic conditions, not a randomized causal A/B comparison with the previous mixed-model run. Full-cycle stops include normal deck-manager assistance; only the prepared-entry observer excludes that assistance.

### Remaining loss

The first aircraft in the three-plane cohort eventually pressed onto final with about 261 m lateral error and 119 m excess height at 997 m remaining. It corrected enough laterally to approach the wire area, but remained roughly 16 m above the selected wire shortly before passing it. It declared a bolter, then collided with the carrier's `Commander` collider at 950.5 s. The callback's 41 m/s is total speed, not vertical impact speed.

This exposes remaining high-path capture and late bolter/obstacle-clearance work. It does not justify declaring the rudder fix a complete landing solution. Next, reduce altitude/energy error before final and verify vertical terminal control plus the resulting bolter escape, rather than widening wires or treating a press attempt as a stable approach.

Prepared-entry pre-contact descent samples still span approximately 5.3–9.4 m/s, and absolute sideways catch speeds 3.8–4.7 m/s. No recorded damage does not imply gentle touchdowns.

### Corrected handoff telemetry

The full-cycle observer previously reported `strict_gate_passed = not diagnostic_override`, incorrectly labelling normal aggressive press attempts as strict passes. It now distinguishes strict, diagnostic and press handoffs and records the flags in per-aircraft cycle results.

The single-aircraft run was recorded before this label correction: its detailed pilot log says `press_commit` and `normal_gate_passed=false`, despite the summary's old strict-pass label. The subsequent three-aircraft run correctly identifies all three final handoffs as press attempts. All six prepared cases also failed the strict final stability gate. No gate thresholds were changed.

## Reproduction and checks

```powershell
.\tools\run_carrier_desert_recovery_test.ps1 -ActiveAircraft 1 -AircraftModel Aircraft_5 -ObserveThroughStow -StrictFinalHandoff -Seed 20260908 -TimeoutMinutes 15
.\tools\run_carrier_desert_recovery_test.ps1 -ActiveAircraft 3 -AircraftModel Aircraft_5 -ObserveThroughStow -StrictFinalHandoff -Seed 20260908 -TimeoutMinutes 15
.\tools\run_landing_turn_in_matrix.ps1 -Repeats 1 -AttemptLimit 6 -TimeoutMinutes 10
```

`-StrictFinalHandoff` disables the test-only forced handoff, not the normal aggressive press policy.

`LandingRecoveryReliabilitySmoketest` passes with added checks for rudder direction, mirror symmetry, measured-turn feedback, bounds, carrier-heading invariance and observer reset. `DesertCarrierRecoveryScenarioSmoketest` and scoped `git diff --check` pass. All three logged runs had zero script/parse errors; existing engine/UI/material/leak warnings remain. No new GA search or visual verification was performed.
