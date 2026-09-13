# Recovery route capture and terrain coordination — 2026-09-08

## Scope and diagnosis

Investigated Aircraft 2's two off-route terrain losses from the preceding
arrestment-stability work. The retained changes use the shared AIPilot; no
aircraft mass, control-power, aero, gear, cable, collider or damage settings
were changed in this task. Final landing and arrestment physics remain intact.

The original traces showed 4–11 m of remaining angular arc length while radial
error grew beyond 3 km, outward velocity approached the whole aircraft speed,
and bank demand collapsed to 0.1–0.4 degrees. Angular progress was incorrectly
treated as a usable tangent exit. The time-to-roll-level limiter overrode the
capture command even though the aircraft was travelling the wrong way.

## Implemented controls and default scope

**Default enabled: telemetry only. All candidate control changes are opt-in.**
The live comparison did not establish a landing benefit, so the previous
flight behavior remains the default. `recovery_route_capture_experimental`
enables capture-aware rollout, finite arc exit and the fast divergence watchdog.
`recovery_recapture_steering_experimental` and
`recovery_capture_terrain_experimental` enable the additional steering/terrain
prototypes. All three default to false. These are implemented experiments,
not deployed reliability improvements. No aircraft scene enables them.

- Separate capture from rollout. The distance/time rollout caps only apply when
  radial displacement and actual velocity support a tangent exit. Off-course
  capture retains the existing airframe-specific bank/load limits.
- Experimental, disabled: outside forward tangent capture, steer toward the circle's capture vector.
  A reciprocal heading cannot null steering through sin(PI). Blend into the
  radial dynamics controller once the aircraft has the right travel direction.
  Preserve its calibrated forward-orbit law instead of retuning established turns.
- Require a nearby, forward-directed arc exit before handing over to the next
  recovery leg. A monotonic angular coordinate cannot advance from kilometres
  away. Ordinary near-endpoint rollout can still hand off without another orbit.
- Detect six seconds of substantial outward divergence at a stalled exit (or
  gross departure beyond three turn radii / 1500 m) and use the existing
  stabilize/replan path. Ordinary initial turn capture keeps the original
  full-turn progress allowance. This clock also runs during an arc's safety override.
- Experimental, disabled: reduced arrival terrain clearance is conditional on tracking a finite route
  capture envelope, including the lineup controller's normal lateral capture
  region. Genuinely off-route arrival restores the ordinary emergency
  margin, currently 180 m.
- Experimental, disabled: off-corridor arrival/lineup adds three forward height samples to the original 20
  fan samples. Its bounded 4–18 s horizon includes roll, sink and climb response.
  Distant obstacles are tested against a conservative possible escape path;
  the original close samples remain unchanged.
- Experimental, disabled: non-imminent recovery clearance warnings become a vertical-speed floor in
  the shared lift-vector controller, preserving the ability to turn and climb
  together. Actual imminent flight-path intersections or very low AGL retain
  the hard emergency override. Downward awareness rays do not masquerade as
  actual flight-path intersections during off-corridor capture. Established
  transit and missed approach retain their original terrain policy.
- Log capture readiness, live safety override, AGL, forward clearance, exact
  intersection distance and the soft vertical-speed floor in landing DIAG lines.

The long forecast is a bounded heuristic, not a guaranteed terrain-avoidance
proof. It does not teleport the aircraft, apply external climb forces or weaken
damage. Sparse height samples cannot establish clearance against every possible
narrow obstacle.

## Iteration and focused verification

Two exploratory versions were stopped deliberately after they showed repeated
route/terrain interference. Their partial stdout/stderr and input snapshots are
preserved under these Godot userdata prefixes; they are not completed successes:

- `random_rtb_20260908_172716_seed_20260908`
- `random_rtb_20260908_172727_seed_20260909`
- `random_rtb_20260908_173217_seed_20260908`
- `random_rtb_20260908_173227_seed_20260909`

The key correction was to distinguish a clearance warning from an imminent
collision. Simply extending a constant-descent forecast, or enforcing every
margin warning by levelling the wings, prevented route convergence.

Completed intermediate-configuration replays (case numbers below are one-based):

| Original loss | Replay report prefix | Outcome | Time | Body contacts / damage |
| --- | --- | --- | ---: | --- |
| Seed 20260908, Aircraft 2 case 6 | `random_rtb_20260908_173652_seed_20260908` | Clean stop | 525.15 s | 0 / 0 |
| Seed 20260909, Aircraft 2 case 3 | `random_rtb_20260908_173702_seed_20260909` | Clean stop | 175.12 s | 0 / 0 |

Both used the original random starting geometry, caught a wire and remained
below 1.5 m/s for the required two seconds. Both had zero payout-limit
corrections and no wave-offs or bolters. Case 6 still needed substantial route
replanning before final: survival and completion improved, but its 8.75-minute
recovery is not efficient. These replays ran concurrently in separate processes;
the runner parses each process's own stdout and verifies frozen input hashes.
The simulation is not bitwise deterministic.

`RecoveryRouteCaptureSmoketest.gd` passes checks for both turn directions,
recorded runaway states, reciprocal capture, steady-circle feedforward, finite
exit handoff, sustained divergence/reset, checked-corridor membership, bounded
response horizon, long-range ridge detection, sample counts, soft climb warnings
and hard imminent-terrain authority. The deck-envelope, compact-recovery and
random-start generation smoke tests also pass. The older landing-reliability
test reports PASS but emits missing `arresting_cable` fixture-metadata errors;
do not describe that test as error-free. Existing shutdown/resource warnings
are separate from flight outcome validity.

## Mixed-aircraft validation and regression correction

The first fleet comparison, `random_rtb_20260908_174000_seed_20260908`,
completed Aircraft 2 at **4/10 stops**, versus 7/10 previously. It was stopped
during Aircraft 1 after this regression became clear; do not present it as a
completed 30-case batch. Its completed Aircraft 2 report and partial Aircraft 1
logs remain preserved. All ten Aircraft 2 flights reached pre-landing; the six
losses were in final/missed approach, not the original outward arrival runaway.

That rejected version applied its soft terrain policy to all recovery transit
and used a particularly tight tangent-exit tube. Its margin correction also
requested positive climb without first including current sink, and effectively
counted sink twice through the dynamic margin. Those changes disturbed otherwise
recoverable arrivals; fixing the two targeted losses did not establish a net win.

The narrowed revision keeps ordinary forward-orbit control, transit and bolter
terrain policy unchanged. It permits moderate parallel offset at a usable
tangent exit, while still rejecting radial/backwards motion and kilometre-scale
false completion. Off-corridor soft terrain correction includes current vertical
speed and uses the base clearance requirement, not an additional sink buffer.

The next revision, `random_rtb_20260908_175610_seed_20260908`, was also stopped
as an exploratory partial batch after a final/missed-approach loss and a 900 s
timeout. Its fresh-seed case 3 replay, `random_rtb_20260908_175620_seed_20260909`,
reached final but crashed after a late wave-off (169.85 s, MISSED_APPROACH near
the carrier). It did not reproduce the original kilometre-scale arrival
runaway, but was not an end-to-end landing success.

The final bounded revision further restricts the alternative heading-capture
law to missed exits or displacement exceeding a turn radius. The normal body
of a turn retains the original control law. Moderate parallel offsets retain
ordinary rollout and finite exit handoff; the safety envelope includes normal
lineup capture instead of treating every 100–200 m offset as a lost route.
These are finite geometric heuristics, not a claim that every point inside the
capture envelope has been terrain-sampled. The live close terrain fan still runs.

Another bounded experimental comparison was started under
`random_rtb_20260908_180518_seed_20260908`, ten cases each of Aircraft 2, 1 and 5.
It was stopped during Aircraft 2 after further losses. The corresponding
fresh-seed Aircraft 2 case 3 replay, `random_rtb_20260908_180528_seed_20260909`,
ended in a late-wave-off crash at 171.3 s. These experimental runs do not support
enabling the alternative capture steering or terrain retune by default.

`random_rtb_20260908_181520_seed_20260908` tested the conservative default but
exposed a separate watchdog regression and was stopped during Aircraft 2.
Its first divergence intervention occurred with the whole 1414 m arc remaining,
bank around 51 degrees and radius error 615 m. Six seconds was too short to
judge normal heavy-aircraft roll-in; the forced reacquisition caused repeated
route resets and a timeout. The watchdog now reserves its fast intervention
for a stalled exit or gross departure. Initial radial capture retains its
original physically scaled full-turn allowance. The fresh-seed case 3 replay
`random_rtb_20260908_181607_seed_20260909` reached final but failed after a late
wave-off at 168.2 s; it is not a clean-stop result.

## Final comparison and release decision

`random_rtb_20260908_182257_seed_20260908` tested the corrected narrow candidate
(rollout/exit/watchdog enabled, additional steering/terrain disabled). It is an
**interrupted batch, not a completed or input-verified 30-case suite**:

| Model | Previous stops | Candidate stops | Clean / damaged stops | Validation |
| --- | ---: | ---: | ---: | --- |
| Aircraft 2 | 7/10 | 5/10 | 5 / 0 | Completed; tracked inputs passed after this model |
| Aircraft 1 | 10/10 | 9/10 | 8 / 1 | Report completed, but post-model input check failed |
| Aircraft 5 | 10/10 | Not run | — | Runner stopped before launch |

The carrier source model `Models/LandCarrier/Land carrier 3.glb` changed during
Aircraft 1's process (file modification time 18:36:47; process report completed
18:43:18). The runner correctly rejected the changed input and exited before
Aircraft 5. We did not edit or restore that model. Aircraft 1's reported outcomes
are retained for inspection but cannot be treated as a controlled comparison.
The suite JSON remains RUNNING because the existing runner throws on failed
input validation before writing a terminal suite status; it is no longer running.

Aircraft 2 reached PRE_LANDING and touched the carrier in all ten cases. All
five catches stopped cleanly, with zero payout-limit corrections. Its failures
were one-based cases 1, 4, 6, 8 and 10, all **before catching a wire**; three
ended in MISSED_APPROACH and two in LANDING. Mean active recovery time was
288.98 s, maximum 502.13 s (queue excluded). These results are worse than the
previous seven clean stops; there is no demonstrated net reliability gain.

The original runaway case 6 now reached the deck, but contacted its right-wing
collider at about 92 degrees of roll, then its fuselage at about 111 degrees,
and was destroyed without a catch. That is a different failure, not a safe
landing. Fresh-seed case 3, `random_rtb_20260908_182307_seed_20260909`, also
reached final but crashed at 335.55 s after one wave-off, without catching a wire.
That single-case replay completed and passed its input checks.

Aircraft 1 reported ten catches, one post-catch loss, eight clean stops and one
damaged stop; do not generalize Aircraft 2's successful arrestments to the whole
fleet. The changed model prevents attributing its outcomes to this controller.
Both completed main-batch engines crashed at shutdown only after writing their
full reports; no SCRIPT ERROR or Parse Error lines were found. Shutdown remains
an infrastructure issue, not an error-free validation claim.

After the interrupted comparison, the narrow candidate was also made opt-in.
The rollout guard, finite-exit condition and fast watchdog (including its safety
override tick) are all bypassed by default. The additional terrain/steering
prototypes remain disabled. Focused tests explicitly enable these candidates
and also check that the default preserves the original watchdog and arc handoff.
The final default-gating revision passed `RecoveryRouteCaptureSmoketest`.
No fresh full-fleet claim is made for the modified carrier asset.

Next useful experiment: isolate Aircraft 2's touchdown-to-wire and late-wave-off
handoff with matched short approach replays, then revisit the route fix separately.
The present traces justify that diagnostic target, not another increase in control
power, weaker damage or a claim that the route problem is fully solved. Resume a
new frozen-input fleet comparison only when the carrier model is stable.
