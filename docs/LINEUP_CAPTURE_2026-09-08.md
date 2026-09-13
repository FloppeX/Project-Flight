# Early centerline capture and Aircraft 2 handling

## Baseline and scope

Visible normal-time hook-down retry run `visible_landing_retry_20260908_193511`
was stopped at the user's change of direction, not completed as a four-case suite.
All 19 tracked input hashes were unchanged before stopping its own PID 6176.
The first case (1000 m behind, 105 m above carrier root, 60 m/s) stopped after
a wire catch at 419.5 s, with three wave-offs and normal 2.2 m/s touchdown.
Its stop log reports health 150 and damage 0; no final structured suite report
was produced. The second case was unfinished. The other two were not run.

The hook sensor was active on initial finals and redeployed on retry approaches.
The test did not force hook retraction, wave-offs, or successful escape outcomes.

The user observed slow centerline closure. Telemetry corroborates a command-side
restriction: Aircraft 2 was 164 m off-line at 1949 m behind the carrier, requesting
and achieving approximately 12 degrees of bank. The finite-time line controller
also issued infeasible lateral acceleration demands (one sample: 137.6 m/s2),
which could drive excessive load despite the bank restriction. A successful catch
after a declared unreachable crossing also warrants a separate abort-prediction
review; abort thresholds are intentionally unchanged in this experiment.

## Implemented experiment

- Shared PRE_LANDING early centerline-capture bank ceiling: 35 degrees, tapering
  over the 600 m outside the 1000 m handoff deadline to the existing 12-degree
  capture boundary. Centered aircraft retain the gentle settled-bank ceiling.
  The separate quick-turn-in behavior and touchdown bank limits are unchanged.
- Rollout reservation uses the early 35-degree authority rather than assuming
  every capture starts at 12 degrees.
- On recovery lineup straights, bound lateral acceleration to the available bank
  and desired vertical support before deriving load demand. This avoids turning
  a missed finite-time lateral target into excessive climb demand.
- Aircraft 2 roll power 8.5 -> 10.2; yaw power 2.4 -> 3.0. Roll surface rate
  4.2 -> 4.8/s; yaw surface rate 3.0 -> 3.5/s. Pitch, mass, thrust, gear, damage,
  hooks, cables, and escape/abort thresholds unchanged.
- Visible retry mode supports ordinary hook-down approaches, live hook-sensor
  overlay/logging, continued retries, and stopped-catch success criteria.

These are normal player-accessible aerodynamic controls, not kinematic steering.
The profile changes apply to player-flown Aircraft 2 too. Shared capture changes
apply to the other fixed-wing pilots, but their flight behavior needs regression
testing before claiming fleet reliability.

## Checks

PASS: LineupCaptureAuthoritySmoketest, LandingRetryHarnessSmoketest,
GoAroundResponseSmoketest, RandomRTBBatchSmoketest. Existing shutdown object-leak
warnings remain separate from these results.

Capture-only replay `visible_landing_retry_20260908_195147` was stopped after the
first aircraft's third wave-off, before completing either case. It did not land;
the second case was not spawned. All 19 tracked inputs were unchanged. The new
capture used approximately 33 degrees of bank at 2 km with bounded 4.9 m/s2 lateral
demand and about 1G load. One retry reached 124 m from touchdown only 0.2 m off
centerline, but still at 59.4 m/s with actual power about 3%; it aborted with a
predicted high crossing. This is diagnostic evidence, not a reliability gain.

## Additional configuration drag requested during visible review

The user observed excessive approach speed and requested stronger drag for all
planes. Initially tried shared `configuration_forward_drag_scale = 2.0`: longitudinal
configuration multiplier is `1 + 2 * (gear_flap_multiplier - 1)`. This doubles only
the gear/flap increment, not clean drag or lateral damping. Aircraft 1/2/5/14
deployed forward multiplier rises from 5.325 to 9.65 (about +81%). Other fixed-wing
profiles retain their authored gear/flap differences and receive the same extra-
drag scaling. Helicopter physics is untouched. Both simplified and advanced
models and both player and AI controls use the physical drag calculation.

In the simplified model, the former Aircraft 2 nose-aligned drag at 60 m/s was
approximately 1383 N / 1400 kg = 0.99 m/s2, close to gravity's acceleration along
a 6-degree descent (1.03 m/s2), before adding thrust or AoA/induced drag. This
explains why an idle-power descent could be slow to lose speed; it is an estimate,
not a claim to have isolated every force in the live pass.

PASS: LandingConfigurationDragSmoketest verifies clean invariance, stronger
deployed drag, and scale=1 legacy behavior across all nine fixed-wing scenes.
The aero CSV now includes `configuration_forward_drag_mult` separately from the
original raw gear/flap multiplier. Existing object-leak warnings remain.

## Root cause found during drag replay; supersedes the extra-drag trial

`visible_landing_retry_20260908_200322` was stopped incomplete after diagnosing
flap detection. Its first aircraft had waved off; no completed landing result.
All 19 tracked input hashes remained unchanged. Actual throttle returned toward
full power around 57 m/s despite an intended slower final schedule.

`LandingFlapWiringSmoketest` reproduced the underlying defect before the fix:
with real flap position 1.0, SimpleAero's cached flap node was null for Aircraft
1/2/5, detection was false, and their stall thresholds remained 39/50/42 m/s.
Child SimpleAero._ready queried the parent's module registry before the parent
populated it. The failed lookup was never retried. This meant that **authored flap
drag, flap lift and flap-adjusted stall speed were not being used**, invalidating
the earlier numerical assumption that the live tests already had full flap drag.

Fix: cache the actual typed flap node independently of parent registry timing,
with re-resolution if the cached node becomes invalid. Also issue flap commands
independently of already-down/up gear, and compare flap targets (not instantaneous
position) when reversing an in-progress deployment.

The new optional drag scale is now **1.0 by default**, retaining the authored
coefficients while restoring their previously missing effects. Do not claim the
additional +81% multiplier is enabled. Restored full flaps alone multiply
Aircraft 1/2/5/14 gear-only drag by 3.55 and lower effective stall speed by 22%.
No additional lift coefficients, mass, thrust, or abort thresholds were changed.

PASS after fix: real-scene flap wiring, gear-independent deployment/retraction,
and command reversal across all nine fixed-wing aircraft. Aircraft 2's effective
stall speed now reports 39 m/s with flaps, giving a 46 m/s AI landing floor rather
than 57 m/s. Existing wing-node/resource warnings are separate from the PASS.
Go-around response and retry-harness smoke checks also pass after the fix.

Visible post-fix two-case Aircraft 2 replay: `visible_landing_retry_20260908_200946`.
Its 20-file frozen-input manifest additionally includes the flap module script.

## Completed post-fix visible result

Both attempts finished with stopped wire catches and zero body/part damage.
Hooks were active for every sampled LANDING frame. This is two prepared starts
on Aircraft 2, not a fleet reliability percentage or an all-random-start test.
All 20 input hashes remained unchanged and the process exited normally. No
script/parse errors or crash-handler signature occurred; existing startup engine
warnings and shutdown texture/object/resource leaks remain separate issues.

| Start | Result | Duration | Catch speed | Touchdown descent | Wave-off events |
| --- | --- | ---: | ---: | ---: | ---: |
| 1000 m / 105 m / 60 m/s | Clean stop | 22.97 s | 45.89 m/s | 5.10 m/s, HARD | 1 |
| 700 m / 73 m / 60 m/s | Clean stop after rejoin | 251.47 s | 46.47 m/s | 5.12 m/s, HARD | 2 |

Clean stop means no recorded health or part damage, not a soft touchdown.
Both stopped below 1.5 m/s for 2.02 s, with zero arrest hard-stop corrections.
The first's 23 s result is substantially faster than the completed pre-fix 419.5 s
case, but capture/profile changes and the flap fix are bundled relative to that
baseline; the flap-wiring regression establishes the defect separately.

The remaining issues are visible: the pilot declares an unreachable crossing
shortly before a real catch, both touches are hard, and a full retry circuit
still takes minutes. Next: validate the landing sight's near-deck prediction
against actual wheel/hook paths, address late false aborts and descent timing,
then run mixed-aircraft regression trials with the now-working flap physics.
Do not further increase configuration drag solely to compensate for the old
flaps-up detection defect. The optional extra scale remains 1.0.
