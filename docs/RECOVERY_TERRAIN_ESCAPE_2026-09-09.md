# Recovery control ownership and terrain escape — 2026-09-09

## Baseline and diagnosis

The reachability suite `random_rtb_20260908_235013_seed_20260908` completed
with 9/10 stopped catches for each of Aircraft 1, 2 and 5. All 27 catches were
clean; no cases timed out. All three remaining crashes occurred before deck
contact. Aircraft 1 case 6 and Aircraft 2 case 9 crashed during recovery routing;
Aircraft 5 case 9 crashed after a heavily banked wave-off. Terrain contact is
explicit for 2/5 and strongly suggested by position/height data for 1.

Aircraft 5's original trace held +0.96 aileron while rolling through upright to
146.7 degrees. Its landing-sight bank cue is not proof of the active routing
controller's target. A diagnostic-only replay, before the behavioral fixes,
`random_rtb_20260909_012701_seed_20260908`, caught cleanly in 256.25 seconds
with no wave-offs/bolters and did not reproduce that inversion. It did show
unchanged control outputs while a route job was pending.

The production recovery method had two asynchronous-route early returns with
no fresh control calculation. A focused test, seeded with +0.96 roll and -0.35
pitch, reproduced both stale commands before the fix; both assertions pass
afterwards. This confirms a real bug, not sole causation of the original crash.

The go-around controller also capped ordinary climb at roughly 11 degrees,
used a short terrain horizon, and latched altitude clearance even when later
terrain was higher. Off-route recovery protection and divergence checks were
partly hidden behind disabled experimental flags.

## Implemented

- Pending route jobs now actively stabilize bank and vertical speed with the
  existing roll-rate-aware capture and lift/AoA control loops. Severe recovery
  bank above 85 degrees also invokes stabilization irrespective of altitude.
- A response-aware terrain profile samples 1–18 seconds ahead. It includes
  roll-uprighting delay, sink and finite upward acceleration. Its climb cue may
  override the ordinary go-around flight-path-angle cap. Inadequate estimated
  clearance is explicit rather than reported as safe.
- Terrain escape uses the same lift-feedback controller and can command more
  than 1 G with wings level. No new physical forces or control authority added.
- New terrain invalidates prior escape-altitude clearance; rejoining requires
  clearance again. Sampled terrain collision can override before the short
  exact collision ray becomes imminent.
- Recovery arrival/lineup gets reduced clearance only while actually tracking
  its checked corridor. Gross outward arc departures can trigger replanning
  without enabling the broader experimental routing behavior.
- Test-only `RECOVERY_CONTROL` telemetry records the post-control owner,
  roll/pitch/yaw, bank, vertical speed, terrain cue and route-job status.

This is a bounded kinematic decision model, not a full simulation of future
flight or a safety guarantee. It adds eight height samples per sensor update
only for off-corridor recovery and missed approaches; general fan sampling is
unchanged. Aircraft profiles, flaps, gear, collision/damage and cables were not
changed in this iteration.

## Verification

PASS: RecoveryTerrainEscapeSmoketest, RecoveryRouteCaptureSmoketest, GoAroundResponseSmoketest,
LandingSightSmoketest, WireReachabilitySmoketest, RandomRTBBatchSmoketest and
LandingFlapWiringSmoketest. The new regression covers stale controls, pending-job
preservation, lift-based sink arrest, finite response time, unknown terrain,
off-route protection, sampled collision priority, fresh clearance requirements,
go-around climb-cap bypass and inverted recovery control. Existing shutdown
resource warnings remain separate from test assertions.

The runtime probes retain seed 20260908 and the previous failed case indices:
Aircraft 1 case 6, Aircraft 2 case 9, Aircraft 5 case 9. Every probe snapshots
inputs and checks hashes. A stopped catch still requires two continuous seconds
below 1.5 m/s; catching a wire alone is not success.

Results/logs live in:
`C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier`.

Initial post-fix Aircraft 1 probe `random_rtb_20260909_013923_seed_20260908`:
reached final, touched down at 1.86 m/s, caught wire 3 at 36.7 m/s, no wave-offs
or bolters. Subsequently `RightWingDamageCollider` contacted the carrier at
3.965 m/s, bank +10.8 degrees, and was classified as a fatal crash. This is a
different, post-touchdown failure, not a successful recovery. No claim of
reliable terrain avoidance can be made from one successful transit.

`tools/run_recovery_escape_regression.ps1` collects all three probes and gates
the optional 30-case fleet run on three stopped catches. Probe failures retain
their results and defer the larger batch for diagnosis. Current report:
`escape_regression_20260909_014429.json` (NEEDS_REVIEW as intended for Aircraft 1).
An earlier orchestration attempt failed to capture the runner's Write-Host
completion message. Information-stream capture was corrected and checked;
completed Aircraft 1/2 results were resumed, not rerun or discarded.

Aircraft 2 probe `random_rtb_20260909_014130_seed_20260908`: clean stopped catch
after one wave-off, 375.87 seconds total / 355.85 active, touchdown 1.71 m/s.
The go-around began at about 49 m AGL with -2.2 m/s vertical speed. Actual climb
rose to about 18.7 m/s, near wings-level, before it rejoined. No damage.

Aircraft 5 probe `random_rtb_20260909_014429_seed_20260908`: clean stopped catch
in 167.55 seconds, no retries, touchdown 4.99 m/s, no damage. Maximum bank
57.7 degrees. The original inversion did not recur, so this trial does not
demonstrate recovery from that exact upset.

All three probe suites completed with their monitored input hashes verified;
no shutdown engine crash was reported. Nonfatal runtime errors remain:
ComputerStation child setup, missing arresting-cable metadata after release,
dummy-renderer materials and resource cleanup. The fleet run was not started.

These are diagnostic replays, not a new fleet reliability estimate. The starts
match the prior failed cases, but comparison of saved inputs also found carrier
damage-control integration changes in LandCarrier2.tscn, FlightDeckManager.gd,
LandCarrier.gd and project.godot since the older suite. Those pre-existing edits
were preserved. Only AIPilot/LandingSight behavioral changes are ours in this
iteration; a strict code-only causal A/B comparison was not performed.

## Next issue

The Aircraft 1 contact reported the right wing, but its final damage snapshot
shows a destroyed fuselage and an intact wing. `_handle_carrier_body_contact`
calls generic `take_damage`, which explicitly routes damage without shape
information into the fuselage pool. Its damage formula uses carrier-relative
speed; the contact diagnostic's 3.965 m/s is world speed, not that damage input.
The trace therefore should not be described as a 4 m/s fatal-damage threshold.

Next investigate shape-aware, contact-normal impact damage with preserved
contact cooldowns, alongside the bank/clearance during arrest. Do not simply
ignore all wing contact or inflate health to turn this failed catch into PASS.
No collider or damage-law change was made as part of the terrain-escape work.

## Follow-up: contact damage routing only

User elected to defer suspension, adhesion and tipping changes. Carrier body
contacts now pass their physics shape index through the existing cooldown-aware
damage handler. The regional model resolves the contacted part, including a
part destroyed earlier in the same frame, so repeated wing callbacks cannot
spill into the fuselage. Generic unlocated damage still defaults to fuselage;
projectile hit resolution and aircraft without regional damage retain their
existing behavior. Damage magnitudes and fatal-speed thresholds are unchanged.

CarrierContactDamageZoneSmoketest reproduced the old routing failure, then
passed on all nine regional fixed-wing models (1–8 and 14), 54 body-region
contacts, including replaced physics shapes, cooldowns, destroyed-region
callbacks and generic fallback. AircraftContactSignalSmoketest,
AircraftCollisionShapeLookupSmoketest (15 models, 30 configurations), and
FixedWingPartDamageColliderSmoketest also passed. Existing asset/cleanup
warnings remain. No new flight batch was run for this routing-only correction.

Landing is substantially improved, not certified reliable: the last full batch
was 27/30 before the terrain changes, followed by only three targeted replays.
The next validation step is a fresh mixed fleet batch, then normal recovery
through deck handling/stow. Further handling retuning is deferred until new
evidence warrants it.

## Mixed validation started — 08:15, 2026-09-09

Started `tools/run_fleet_recovery_validation.ps1` as hidden background runner
PID 12964. First stage: `random_rtb_20260909_081524_seed_20260908`, ten starts
each for Aircraft 1/2/5, seed 20260908, 900-second simulated attempt limit.
The selected-input manifest now also covers the part-damage model, wing collider
follower, AirOps manager/director and carrier damage-control integration.

After a complete, hash-verified batch, the runner automatically executes the
mixed finite deploy/launch/return/land/stow scenario with ActiveAircraft=3,
TargetTraps=3, ObserveThroughStow and StrictFinalHandoff. Aircraft losses are
reported rather than used to skip this independent operational test. Missing
terminal results or changed monitored inputs stop the pipeline for review.
Normal handling and the existing damage amounts remain unchanged.

Current status/results are pending, not PASS. No recurring monitor was created.
The runner itself owns the queued second stage. Observer and random-batch
smoke tests exited successfully before launch; existing cleanup warnings remain.

Files in the Godot user-data directory:

- `fleet_recovery_validation_20260909_081524.json`: pipeline stage and result paths.
- `fleet_validation_runner_20260909_081524.stdout.log` / `.stderr.log`: runner output.
- `random_rtb_20260909_081524_seed_20260908_*`: per-model flight evidence and inputs.
