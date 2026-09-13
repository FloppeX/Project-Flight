# Aircraft_5 landing reliability — 2026-09-08

Final verification: **6/6 held-out entries caught and stopped unassisted**, with health 100 and zero recorded damage. This is a promising controlled-test result, not a demonstrated all-conditions landing success rate.

Follow-up: the [mixed full recovery cycle](MIXED_FULL_RECOVERY_CYCLE_2026-09-08.md) launched and recalled Aircraft_1/2/5 but recorded zero catches/stows. Aircraft_5's normal route exposed a suspected PRE_LANDING bank/rudder coordination gap; the prepared-entry result did not generalize.

## Scope and changes

The new flight-control behavior is enabled on Aircraft_5 only. Aircraft_1/2 tuning, aircraft physics, hook geometry, and the user's wire spacing were not changed in this iteration. Shared bolter/arrest sequencing and the test harness were corrected.

- Energy-aware final throttle: low-path rescue power tapers away when already substantially above approach speed; near-stall protection remains. Previously the rescue floor could demand about 90% throttle at 86 m/s against a 46 m/s speed schedule.
- Acceleration-aware lateral guidance: plan for both centreline position and low sideways velocity at the wire, with a bounded lateral acceleration and a nominal response delay. The forecast is approximate, not a proof of reachability. It still commands ordinary aerodynamic controls, never aircraft transforms or velocity.
- Begin the sight-guidance blend at 1,800 m rather than waiting until 700 m. Blend vertical sight guidance during PRE_LANDING as well.
- Give the new bank controller sole ownership of its smoothed roll command. PRE_LANDING was mixing in the old navigation command; FINAL was updating the same smoothed roll twice. Removing these competing updates was the largest observed improvement.
- Determine the final bolter boundary from the actual hook and last wire, not a fixed distance beyond the wheel touchdown marker. An engaged wire takes precedence over approach gates; cable release hands control to normal deck recovery.
- Test success now requires a caught aircraft to remain below 1.5 m/s relative to the carrier for two continuous seconds. Engagement is provisional. Destruction after engagement remains a crash; damage, health, stop status and recovery status are separate fields. Failure to settle within 12 seconds is ARREST-FAIL.
- Observer-owned test aircraft are excluded from all three deck-recovery entry paths: engagement handling, stopped-aircraft polling, and direct post-arrest recovery requests. Otherwise recovery pickup can zero their velocity and contaminate the stop measurement.
- Record the last pre-contact descent sample separately from collision-callback velocity. Neither is asserted to be exact impact velocity; damage physics are unchanged.
- GA fitness version 41 requires a stopped catch and penalizes damage and sideways catch speed. No new long GA search was launched.

## Experiments

Files below are under `C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier`. Each run has a `.json`, `.stdout.log`, `.stderr.log` and `.report.log` with the stated stem. Cases are deterministic controlled entries, not independent random trials or full launch/mission/recovery cycles.

| Run stem suffix | Configuration | Observation |
| --- | --- | --- |
| `20260908_015406` | Energy-aware throttle alone, right 60 m/s entry | Crashed. Slowing an aircraft without correcting its approach geometry was insufficient. |
| `20260908_020045` | Earlier acceleration guidance, competing roll updates still present | Crashed; about 210 m off centreline at 350 m remaining. |
| `20260908_020433` | Removed competing roll updates | Caught and stopped; 4.6 m off centreline and 55.7 m/s at 350 m remaining. |
| `20260908_020709` | Six standard entries, left/right at 50/60/70 m/s | Six caught/stopped, health 100, recorded damage zero; catch speeds about 54–58 m/s. Stop measurement was not yet fully isolated from deck recovery. |
| `20260908_020955` | Six held-out entries: +5 m/s, +100 m lateral run-in, +15 m altitude | Six caught/stopped with zero recorded damage, but the direct recovery request could still intervene. Do not count these as proof of an unassisted stop. |
| `20260908_021749` | Repeat held-out entries with all recovery intervention paths excluded | Six unassisted caught/stopped, each below 1.5 m/s for 2.017 s, health 100, damage zero. No recovery interventions or script/parse errors in the log. |

Final isolated batch: left/right initial speeds 55/65/75 m/s; catch speeds 54.4–57.7 m/s; absolute sideways catch speeds 2.6–4.5 m/s; pre-contact sampled descent 6.9–10.2 m/s. No bolters, wave-offs, crashes or timeouts. Only one of six passed the strict final stability gate, so the result still depends on the existing aggressive press behavior. Recovery status remained `not_exercised` throughout.

## Remaining limitations

- Bank oscillation remains. All six standard entries failed the strict stability check at the final gate; one of the first six holdouts passed. The already-enabled aggressive press behavior continued the others. Gate thresholds were not relaxed here.
- These are not yet gentle landings. Pre-contact sampled descent was about 6–10 m/s in the successful batches, often substantially greater than the collision callback reported. Zero damage is a result of the existing simulation, not evidence that the approach is physically gentle.
- The matrix's historical `rollout_*` JSON fields describe PRE_LANDING entry, not a proven wings-level rollout 1,000 m behind the carrier. Console wording now says entry/pre_landing.
- The full operational route, moving or poorly placed carriers, traffic sequencing, and recovery through hangar storage remain unverified by these isolated tests.
- Next validation should preserve this baseline, exercise a full Aircraft_5 launch/recall/recovery cycle, and then tune bank damping and vertical terminal energy separately. Avoid a broad GA search until its success signal is trustworthy.

## Reproduce

```powershell
.\tools\run_landing_turn_in_matrix.ps1 -Repeats 1 -AttemptLimit 6
.\tools\run_landing_turn_in_matrix.ps1 -Repeats 1 -AttemptLimit 6 -HoldoutEntries
```

Run matrices sequentially: they share the live landing report. `-GuidanceVariant baseline` disables the new energy/lateral controls and restores the older sight blend distances, but retains current shared safety/sequencing and harness fixes; it is not a byte-for-byte replay of an old revision.

Focused checks passed: `Tests/LandingRecoveryReliabilitySmoketest.gd`, `Tests/LandingSightSmoketest.gd`, `Tests/LandingTestHarnessSmoketest.gd`, and `tools/landing_ga_tuner_smoketest.gd`. The new reliability check covers energy rescue, bounded/mirrored terminal guidance, moved last-wire boundaries, catch precedence, sustained-stop reset, damage/destruction, released catches, and prevention of test-owned recovery stabilization.

Main-scene headless runs still emit existing UI/material/camera warnings and exit resource-leak warnings. They are not a clean visual or performance verification.
