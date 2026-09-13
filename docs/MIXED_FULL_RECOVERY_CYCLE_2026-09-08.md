# Mixed deploy / launch / return / land / stow observation

## Result

**FAIL: 3 deployed and launched, 3 recalled and returned, 0 wire catches, 0 stopped catches, 0 stowed.** The finite cohort was one Aircraft_1, one Aircraft_2 and one Aircraft_5, with no replacements. The run ended naturally after all three were destroyed, at scenario time 1,523.3 s (25 min 23 s).

| Model | Launch | Return order | Furthest stage / outcome |
| --- | --- | --- | --- |
| Aircraft_1 | 15.1 s | 121.0 s | Entered LANDING at 407.7 s via a press handoff. Destroyed on carrier contact at 427.4 s, before a wire catch. |
| Aircraft_2 | 33.8 s | 122.0 s | Two logged handoff wave-offs; four recovery-approach entries. Eventually destroyed in terrain contact at 1,523.3 s, still in RECOVERY_APPROACH. |
| Aircraft_5 | 48.8 s | 173.7 s | Two logged handoff wave-offs; three recovery-approach entries. Eventually destroyed in terrain contact at 1,502.8 s, still in RECOVERY_APPROACH. |

All three reached PRE_LANDING. Only Aircraft_1 reached LANDING. Damage signals reported 100 / 150 / 100 respectively, with final health zero. Neither terrain impact proves fuel starvation; this run did not establish the reason for the final loss of energy/terrain clearance.

Later telemetry correction: the original observer mislabeled non-diagnostic press handoffs as strict passes. Aircraft_1's detailed pilot log records `press_commit`, failed track/bank/stable-time checks, and `normal_gate_passed=false`. The observer now reports these modes separately. See the [Aircraft_5 input fix and subsequent runs](AIRCRAFT_5_COORDINATED_LANDING_INPUTS_2026-09-08.md).

No aircraft reached the towing/storage portion, so actual stow behavior remains **unexercised**, not diagnosed as broken. Launch provisioning and the initial deck/catapult sequences did execute successfully for all three.

## What the run exposed

### Aircraft_1: contact problem, not failure to line up

At the last sight sample before destruction, the aircraft was about 0.3 m off centreline, 1.3 degrees off track, and descending about 7.2 m/s. The destruction callback named the carrier as the collider, with bank 0.6 degrees and total speed 46.5 m/s. Total callback speed is not the vertical impact speed.

This is consistent with the previously reported Aircraft_1 landing-contact problem. It does **not** distinguish a suspension/collider defect from an excessively hard touchdown. Inspect pre-impact contacts and suspension behavior separately before tuning its guidance around this failure.

### Aircraft_2: approach arrives too far out of position

The two handoff rejections near 1,000 m remaining were approximately:

- 270 m lateral error and 121 m above the desired path, at 69.1 m/s.
- 430 m lateral error and 224 m above the desired path, at 68.9 m/s.

The new Aircraft_5-specific acceleration and energy controls are not enabled on Aircraft_2. Shared recovery changes alone did not produce a successful landing in this run.

### Aircraft_5: nominal bank acceleration is not achieved

The two handoff rejections were approximately 289/293 m lateral error and 83/67 m above the desired path, at about 69.5 m/s.

On the first attempt, from 1,219 m to 1,008 m remaining, the new lateral plan continuously requested -4 m/s². Actual and requested bank both stayed near +22.2 degrees, but lateral velocity only changed from +3.2 to +2.5 m/s; lateral error increased from +281 to +290 m. Rudder command remained zero. Thus more roll authority alone is unlikely to solve this particular interval: the bank was already achieved.

The code supplies a plausible explanation:

- `AI/AIPilot.gd`, `_state_pre_landing`: the new acceleration-guidance branch explicitly sets `yaw_input` and its smoothing state to zero after running the normal route controller.
- `AI/AIPilot.gd`, AI aerodynamic overrides: `SimpleAero.auto_rudder_strength` is also set to zero while the AI is in control.
- `Aircraft/SimpleAero.gd`: slip alignment applies a force toward the aircraft's forward direction. A commanded bank does not by itself guarantee the coordinated-turn acceleration assumed by `-atan2(acceleration, 9.8)`.

This is a strong candidate for the missing control behavior, not a completed causal test. Restore coordinated rudder under the same terminal objective and close the loop on measured lateral acceleration/track response; compare against this unchanged run. Do not simply reintroduce the old competing waypoint steering command.

The previous prepared-entry 6/6 result does not generalize to this full recovery route. Normal route-to-final altitude/energy preparation also remains a separate problem; the energy-aware throttle change acts in LANDING, which Aircraft_5 never reached here.

## Test configuration and harness changes

```powershell
.\tools\run_carrier_desert_recovery_test.ps1 -ActiveAircraft 3 -TargetTraps 3 -ObserveThroughStow -StrictFinalHandoff -Seed 20260908 -TimeoutMinutes 20
```

The existing desert scenario stages a stationary carrier on a terrain-checked site, uses actual hangar retrieval/catapult launches, disables combat, and recalls aircraft after the halfway point of nominal 10 km outbound legs plus a short delay. It retains its existing skill/climb/test configuration. No aircraft tuning, physical colliders, hook geometry or cable spacing was changed in this turn. The test-only forced-final-handoff override was disabled; normal press behavior was not retuned.

`-ObserveThroughStow` now keeps a finite cohort running after the first loss or catch. It caps lifetime launches, records each aircraft through destruction/storage, and observes the actual `FlightDeckManager.aircraft_stored` event emitted after stock insertion. Storage cannot be inferred from an aircraft merely disappearing. The observer has a 2,400 s simulated-time limit; this run finished before it.

The summary's legacy `friendly_crashes` counter remains zero in this observation mode because raw crash callbacks are tracked separately instead of immediately terminating an aircraft. The per-aircraft destruction fields and `friendly_destroyed=3` are the authoritative loss result here. Stop observations in this full-cycle mode include normal managed deck recovery; they are not claims of an unassisted arrest.

Focused checks passed: `FullRecoveryCycleObserverSmoketest` (catch alone insufficient, first loss does not abort others, true storage required, destroyed cohort cannot pass), `DesertCarrierRecoveryScenarioSmoketest`, and scoped `git diff --check`. The run had zero script/parse errors, but existing main-scene warnings must not be confused with a clean visual/performance verification.

## Evidence

Run ID: `desert_recovery_20260908_023118_seed_20260908`.

Files under `C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier`:

- `carrier_combat_test_desert_recovery_20260908_023118_seed_20260908.log`: scenario timeline and terminal `RUN_RESULT` JSON.
- `desert_recovery_20260908_023118_seed_20260908.stdout.log`: landing sight, bank-plan, gate-rejection and collision evidence.
- `desert_recovery_20260908_023118_seed_20260908.stderr.log`: engine diagnostics.
