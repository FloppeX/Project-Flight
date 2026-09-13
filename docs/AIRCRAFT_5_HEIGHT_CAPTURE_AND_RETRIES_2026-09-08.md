# Aircraft 5: height capture, high misses and finite retry holds

Final verification: **3/3 full recovery cycles stowed undamaged**, **6/6 held-out
turn-ins caught/stopped unassisted**, and a **200 m wave-off followed by actual
clearance, rejoin, catch, stop and stow**. The extreme high-entry cases still
abort instead of landing; this is not an all-conditions reliability claim.

## Plan and scope

1. Preserve the working lateral controller and its ordinary player-equivalent
   aerodynamic inputs. Reduce excessive height before short final.
2. Detect a clearly high miss of every remaining wire early enough to request
   the existing missed-approach controller. Do not reject merely lateral errors.
3. Exercise full deploy/launch/return/catch/stop/stow cycles, standard and held-out
   turn-ins, and deliberately high entries. Keep GA optimization deferred.
4. The logged operational runs also exposed an unqueued exception hold after
   three failures. Give Aircraft 5 a timed local retry, and admit its observed
   20-35 degree handoff bank rather than rejecting a usable 1,000 m final.

All new pilot behaviors are opt-in on Aircraft_5. Aircraft_1/2 and other airframe
tuning are unchanged. No aerodynamic forces, damage thresholds, collider
geometry, hook reach, wire spacing, or flight transforms were changed.

## Implementation

- `LandingSight.high_path_capture_sink_mps` aims excess height at a point
  350 m before the selected wire. The commanded descent allowance tapers from
  up to 22 m/s well outside final to the original 12 m/s terminal limit.
  Below/on-path approaches keep their original cue. A 1.5 s descent-rate lead
  starts unwinding the extra descent before momentum carries the plane low.
  This bounds the request, not the aircraft's actual physical sink rate.
- Aircraft 5's high-miss decision considers every remaining wire over a maximum
  four-second horizon. It optimistically permits an instantaneous transition
  to maximum terminal descent after 0.6 s. Only when even that projection is
  above every wire's tolerance plus 1 m, continuously for 0.25 s, does it abort.
  A reachable later wire, missing telemetry, or physical arrest prevents this
  decision. Existing low-path, terrain and busy-deck checks remain.
- Aircraft 5 permits up to 35 degrees of existing bank at the 1,000 m aggressive
  handoff, instead of 20. This is permission to enter final, not extra aileron
  authority. The existing 30-degree outer control limit and taper toward
  12 degrees on short final / 8 degrees at touchdown remain unchanged.
- After the three-attempt budget expires, Aircraft 5 waits 20 s locally, resets
  that batch's attempt budget and requests a new slot through the ordinary deck
  queue. It does not grant itself clearance or bypass terrain checks. Other
  models retain the existing supervised exception behavior. Retry batches emit
  `RECOVERY_RETRY` and are counted in aircraft metadata.
- Added three prepared high-path cases, explicitly labelled as synthetic press
  entries, alongside the original 13 straight-in cases. They do not prove a
  strict final handoff.
- Corrected the combined forced-waveoff/stow observer: clearance is an
  intermediate milestone, not an immediate test exit. Passing the combined test
  now requires both actual escape clearance and caught/stopped/stowed recovery.
  A very late wave-off that still catches a wire cannot masquerade as a cleared
  escape. The standalone escape-only test still finishes on clearance.

## Logged evidence

Run files are under
`C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier`.
Full-cycle logs are `carrier_combat_test_<run ID>.log` plus `<run ID>.stdout.log`
and `.stderr.log`. Matrix runs also write JSON and `.report.log` artifacts.

| Run ID | Configuration | Result |
| --- | --- | --- |
| `desert_recovery_20260908_075228_seed_20260908` | Fresh baseline, three Aircraft 5s | 2/3 stowed healthy; third destroyed on terrain during recovery approach. |
| `desert_recovery_20260908_075923_seed_20260908` | Initial height/escape changes only | 2/3 stowed healthy; remaining aircraft rejected three times and eventually lost from unqueued hold. |
| `desert_recovery_20260908_080703_seed_20260908` | Added handoff bank allowance and retry cooldown | 3/3 caught, stopped and stowed, health 100 and zero damage. Before final descent-lead/margin refinement. |
| `desert_recovery_20260908_081207_seed_20260909` | Final pilot settings, different seed | 3/3 caught, stopped and stowed, health 100 and zero damage; stored at 354.8, 580.2 and 725.8 simulation seconds. |
| `landing_turn_in_matrix_20260908_075933` | Six standard left/right 50/60/70 m/s entries | 6/6 caught and stopped unassisted. Initial height/escape version; no wave-offs, crashes or timeouts. |
| `landing_sight_matrix_20260908_081131` | Final settings, high +120 m, high +80 m with offset, late high +50 m | Three wave-offs, no catches or recorded crashes before abort. |
| `landing_turn_in_matrix_20260908_081550` | Final settings, six held-out left/right 55/65/75 m/s entries, added offset and height | 6/6 unassisted stopped catches, health 100, damage 0, no wave-offs/crashes/timeouts. |
| `desert_recovery_20260908_081540_seed_20260908` | Final settings and corrected observer, forced wave-off at 200 m then full recovery | PASS: triggered at 199.1 m, cleared, returned, caught at 448.2 s, stopped at 454.3 s, stowed at 482.8 s; health 100, damage 0. |

Every final held-out catch stayed below 1.5 m/s for 2.017 s with recovery
interventions excluded. Pre-contact sampled descent ranged from 6.3 to 8.5 m/s,
so these are not necessarily gentle touchdowns. Four entries handed directly
from recovery approach into final without recording a PRE_LANDING stage; the
sentinel entry metrics for those cases are not real rollout measurements.

The three high cases are **not landing successes**. The +120 m and late +50 m
cases trigger the new high-miss check; the +80 m/offset case ultimately triggers
the existing low-path check. This is outside the demonstrated capture basin.
These finite tests stop at wave-off and do not measure subsequent escape.

The first prepared high run used ordinary strict-final mode and was rejected by
the older cone check. It is not evidence for the new press-mode logic. The first
proper press run (`landing_sight_matrix_20260908_080713`) had one crash and two
wave-offs; that motivated descent anticipation and reducing the high-miss margin
from 4 m to 1 m. The final repeat no longer recorded that crash before abort.

`desert_recovery_20260908_080306_seed_20260908` requested a wave-off at 49.2 m
but still caught a wire and stored undamaged. Its old PASS summary is not proof
of escape: `cleared=false`.
`desert_recovery_20260908_081142_seed_20260908` verified actual clearance after
a request at 199.7 m, health 100, but exposed the combined observer's premature
exit. Its FAIL summary predates the observer correction and does not represent
an aircraft crash.

## Regression checks

- LandingRecoveryReliabilitySmoketest: height capture bounds, low/on-path
  preservation, descent anticipation, all-wire high-miss policy, hysteresis,
  arrest precedence, opt-in retry cooldown, missing-reference guard and queue
  ownership, alongside the existing lateral/energy/arrest checks.
- LandingSightSmoketest: existing observer, moving deck, geometry and cue checks.
- LandingTestHarnessSmoketest: 16 straight-in cases, six turn-in cases, unchanged
  GA curricula, preserved recovery hardware, Aircraft_5-only opt-in settings.
- FullRecoveryCycleObserverSmoketest: combined escape must continue through
  recovery, cleared escape cannot later time out, standalone escape still ends,
  and a catch without escape clearance cannot pass the combined test.
- DesertCarrierRecoveryScenarioSmoketest: existing queue, routing, recovery
  stage and forced-waveoff contracts.

These focused checks pass. Full-scene runs still emit unrelated startup
ComputerStation add-child/material warnings; headless shutdown resource warnings
also remain. These are not visual or performance tests.

## Reproduce

```powershell
.\tools\run_carrier_desert_recovery_test.ps1 -ActiveAircraft 3 -AircraftModel Aircraft_5 -ObserveThroughStow -StrictFinalHandoff -Seed 20260909 -TimeoutMinutes 15
.\tools\run_landing_turn_in_matrix.ps1 -Repeats 1 -AttemptLimit 6 -HoldoutEntries -TimeoutMinutes 10
.\tools\run_landing_sight_matrix.ps1 -AircraftModel Aircraft_5 -StartCase 13 -AttemptLimit 3 -TimeoutMinutes 10
.\tools\run_carrier_desert_recovery_test.ps1 -ActiveAircraft 1 -AircraftModel Aircraft_5 -ObserveThroughStow -StrictFinalHandoff -ForceWaveoffAtM 200 -Seed 20260908 -TimeoutMinutes 15
```

Run the two matrix suites sequentially; they share the live landing report.
`StrictFinalHandoff` disables a test-forced handoff, not the normal aggressive
press policy. All successful operational finals above were press handoffs.

These are small scenario samples, not a statistically established reliability
rate or a deterministic causal A/B experiment: threaded route timing can vary
even with the same seed. The next useful work is expanding the demonstrated
height/energy capture basin and testing difficult carrier placement, not changing
wire geometry or launching a broad GA search based only on these successes.
