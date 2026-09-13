# Shared recovery envelope — 2026-09-08

## Evidence and plan

Baseline: `RANDOM_RTB_BATCH_2026-09-08.md`, seed 20260908, ten matched
500–1000 m / 8 km airborne RTB starts per model. Aircraft 1/2/5 stopped
5/7/5 times respectively (17/30 total). This is a training comparison set,
not an independent reliability estimate.

The principal failure groups were:

- Aircraft 5: all trials reached final, with five raw CRASH results around
  deck entry. Several projected a hook/deck-plane intersection outside the
  physical deck, and some retained substantial sideways speed. One result was
  a survivable 3.7 m/s contact signal, not confirmed destruction.
- Aircraft 1: four terrain failures before final, plus one post-catch loss.
- Aircraft 2: prolonged recovery turns at insufficient available lift, and
  terrain exposure during missed approaches.

Implement shared geometric and energy constraints before per-aircraft gain
optimization. Preserve each aircraft's mass, control-surface strengths, and
collision geometry. Continue using ordinary pilot controls, without position,
velocity, arrestor-volume, or damage-rule overrides.

## Retained implementation

1. **Finite stern clearance.** Read the carrier collision setup's actual hull
   bounds and the lower main-wheel support point. Ask for enough vertical
   clearance to put that wheel 1.5 m above the hull until five metres inside
   the stern. Account for 0.8 s response delay; begin considering the envelope
   within 650 m. The final pitch path respects this floor after ordinary
   tracking smoothing. This is bounded input guidance, not guaranteed collision
   avoidance. It does not yet model every wing/body vertex or elevator opening.
2. **Earlier lateral settling.** Target zero lateral displacement and speed
   four seconds before the wire; blend into damped centreline holding on short
   final. This removes the shrinking-time-to-go singularity at touchdown while
   retaining the existing bounded acceleration and rudder coordination.
3. **Roll control and terrain escape.** Final approach uses the aircraft's
   actual inertia, available roll torque, and damping to brake roll before
   crossing the commanded bank. Terrain escape actively rolls returning
   aircraft upright instead of sending neutral aileron and retaining the turn.
   Missed-approach escape altitude also considers terrain two, four, and six
   seconds along actual velocity, plus 100 m.
4. **Physical deck-side reach.** Within four seconds of the stern, allow maximum
   lateral correction after actuator delay. Escape only when even this
   optimistic correction cannot reach the physical deck width with a five-metre
   wheel/edge margin. Existing retry/queue rules remain in charge.
5. **Truthful contact observation.** Record resolved self-collider name,
   physics indices, safe-wheel classification, other body, and health. A legacy
   `crashed` signal with surviving health no longer ends a trial prematurely;
   the observer continues to destruction, stopped arrest, or timeout. Retain
   body-contact signal counts and terminal health in results. Damage physics
   and the legacy aircraft signal contract remain unchanged.

The last point changes measurement for surviving body scrapes: raw CRASH counts
are not strictly comparable in those cases. Sustained stops are the primary
comparison metric, with body contacts and touchdown severity reported separately.
They must not be equated with damage-free recoveries.

## Validation

### Diagnostic iteration and correction

`random_rtb_20260908_121620_seed_20260908` was intentionally stopped after six
Aircraft 1 trials (two stops, four losses), with its logs and input snapshots
retained. It is a partial diagnostic, not a completed 30-case comparison.

The trace exposed a direct terrain-controller defect: the "level the wings"
fallback sent neutral aileron, retaining a recovery turn's bank while trying to
climb. Recovery terrain escape now actively drives bank and roll rate to zero.
Final approach also replaces the high-gain bank-error-only servo with the
airframe-derived roll-rate/braking controller already used by navigation.

One other loss reached the deck at 31 m lateral offset. A four-second,
optimistic lateral-reach check now requests escape if maximum correction still
cannot reach the actual deck width (five-metre wheel/edge margin). It does not
require a perfectly centred approach. Destruction is recorded separately from
health because a fatal part failure can leave the aggregate health unchanged.

The next diagnostic (`random_rtb_20260908_122333_seed_20260908`) completed
Aircraft 1 at 10/10 normal, full-health stops, zero body-contact signals and
zero retries. Its largest absolute sideways speed at catch was 0.53 m/s.
Aircraft 2 exposed an implementation coupling: limiting bank without scaling
the requested vector magnitude redirected lateral lift into an unwanted climb.
That pass was stopped during Aircraft 2; it is not a complete fleet result.
An intermediate correction preserved the planned vertical force while scaling
total load; that limiter and its dedicated regression were subsequently removed.

Further partial diagnostics (`123545` and `124803`, same date and seed) explored
coupled bank/load limiting, climb-arrest priority, wider terrain sampling, and
predictive terrain-triggered replanning. They exposed poor Aircraft 2 route
behaviour, including a new timeout and terrain loss. These broader navigation
experiments were **removed**, together with their unused helpers and test-only
fixture. The initial 10/10 Aircraft 1 result therefore describes an intermediate
version, not the final retained version. No partial pass is pooled into the
final fleet comparison.

Final verification is `random_rtb_20260908_125430_seed_20260908`, starting
Aircraft 5, then 1 and 2, preserving ten identical starts per model. The
`-FirstAircraft` option changes only test order, not geometry or trial count.

Focused regression checks passed during this change:

- LandingRecoveryReliabilitySmoketest: finite stern/lateral reach, roll braking,
  active recovery terrain levelling, retry policy,
  survivable-contact observation, and sustained arrested stops.
- RecoveryDeckEnvelopeSmoketest: hull-relative geometry at four headings,
  post-stern release, and the lower wheel of a banked aircraft.
- RandomRTBBatchSmoketest: all three configurations and ten paired start bounds.
- AircraftCollisionShapeLookupSmoketest: 15 aircraft, 30 shape configurations,
  264 safe-gear and 124 body contacts.
- AircraftContactSignalSmoketest, LandingSightSmoketest, LandingTestHarnessSmoketest.
- FullRecoveryCycleObserverSmoketest: observer state logic only, not a new
  airborne deploy/launch/stow test. Fixed its standalone test's premature
  global-class reference so dependencies load after autoload registration.

### Completed matched batch

All 30 trials finished. All eight randomized geometry fields match the baseline
per aircraft and case (tolerance 0.001), not merely across the new fleet. All ten
saved source/scene input hashes matched the working files at completion.

| Aircraft | Baseline stopped | Retained stopped | Normal / hard stops | Other outcomes |
| --- | ---: | ---: | ---: | --- |
| 1 | 5/10 | 10/10 | 10 / 0 | None; one slow body scrape after arrest |
| 2 | 7/10 | 8/10 | 0 / 8 | One destroyed, one 900 s timeout |
| 5 | 5/10 | 9/10 | 2 / 7 | One destroyed |
| Total | 17/30 | 27/30 | 12 / 15 | Two destroyed, one timeout |

These are stopped arrests held for at least two seconds, not a new verification
of taxiing, stowing, or repair readiness. The observed stop rate rose from 57% to
90% on this tuning seed; ten trials per model are not enough to establish general
reliability. Cases use a stationary carrier and the same 90 m/s initial speed.

Maximum absolute lateral speed at catch was 0.48, 0.63 and 0.65 m/s for aircraft
1, 2 and 5 respectively. Successful-return mean / maximum durations were
341 / 643 s, 366 / 778 s and 275 / 746 s. Long routes and retry/queue delays remain.

Remaining failures (one-based case numbers):

- Aircraft 5 case 1 missed the wire, then was destroyed when its horizontal-
  stabilizer collider hit carrier structure during missed approach. The first hook pass was only
  slightly above the wire's vertical capture tolerance; the next escape was late.
- Aircraft 2 case 1 also hit carrier structure during a bolter/missed approach
  (left-wing body collider). Case 4 exhausted 900 s after two wave-offs.
- Aircraft 1 case 9 stopped, but its right-wing body collider contacted the
  carrier at 0.455 m/s after arrest. This is a successful stop with a scrape,
  not evidence of an undamaged aircraft.

### Regional damage telemetry correction after the batch

The aircraft's regional damage system intentionally leaves `current_health`
unchanged and can bypass the legacy `damaged` signal. Therefore full aggregate
health and `damage_taken=0` in this completed batch do **not** prove no damage to
individual parts. The Aircraft 1 scrape is specifically flagged for that reason;
its exact regional loss was not captured and is not reconstructed here.

After verifying the batch input hashes, the observer gained passive terminal
`part_damage_state`, `part_damage_observed`, and summed `part_health_loss` fields.
Missing regional evidence is marked unavailable with loss -1, never zero. This
does not alter aircraft controls, collision rules, or outcome arbitration. The
completed batch predates these added fields; its original input snapshot remains
the exact record of what ran.

LandingDamageTelemetrySmoketest passes on all three real aircraft: applying ten
points of regional damage leaves aggregate health unchanged while the observer
reports ten points of loss. Missing APIs remain explicitly unavailable.

### Next iteration

1. Add a short deck-obstacle clearance trajectory for late bolters, including
   tail/wing geometry and pitch-response delay, before another fleet-wide run.
2. Reduce Aircraft 2/5 sink rate with earlier energy/attitude settling; retain
   the finite-stern floor and require regional damage evidence when judging success.
3. Investigate Aircraft 2's timeout/long routes separately from final control.
4. Validate on unseen seeds, varied entry speeds, and moving carriers; then
   exercise the complete deploy/launch/return/stow cycle. Do not optimize a GA
   against aggregate health or this single seed alone.

Input snapshots and per-process logs are preserved by
`tools/run_random_rtb_batch.ps1`. The complete result is
`C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier\random_rtb_20260908_125430_seed_20260908.json`.
No SCRIPT ERROR or Parse Error occurred in the three retained flight processes.
All three nevertheless reported existing startup/material errors and a Godot
shutdown crash **after** emitting complete results; these are infrastructure
warnings, not clean process exits. Normal headless smoke exits also report
existing ObjectDB leak warnings.
