# Project Flight carrier recovery investigation

**Date:** 2026-07-31  
**Scope:** Comparison of the working isolated landing test with the mixed/full-cycle scenario, based on the current source tree and the named logs below.

## Implementation update (2026-08-01)

The upstream recovery controller now has explicit end-to-end catch evidence from five additional far/very-far dirty entries. All five catches completed without a wave-off or bolter:

| Case | Entry | PRE_LANDING | Wire | Maximum carrier distance | Result |
|---|---:|---:|---:|---:|---|
| `far_high_away` | 13.5 km | 287.1 s | 322.9 s | 15.175 km | Caught |
| `far_low_inbound_heavy` | 14.0 km | 156.6 s | 208.8 s | 14.017 km | Caught |
| `very_far_hot` | 18.0 km | 407.9 s | 458.6 s | 19.419 km | Caught |
| `very_far_cold` | 19.0 km | 369.9 s | 409.8 s | 19.945 km | Caught |
| `very_far_cross_heavy` | 20.0 km | 327.6 s | 379.5 s | 20.139 km | Caught |

The `far_low_inbound_heavy` route initially caught but produced a 25.3 km, 42-leg arrival and did not reach `PRE_LANDING` until 342.2 seconds. A guarded behind-join staging path now keeps an aircraft that is already well behind the carrier and tracking inbound from flying to an ahead-of-carrier staging point. On the same deterministic case, this reduced the route to 20 legs / approximately 11.7 km, moved `PRE_LANDING` to 156.6 seconds, and moved the wire catch to 208.8 seconds. The terrain, turn-dynamics, final geometry, and stable-time gates were not relaxed.

The final handoff defect found in `far_high_away` was also corrected without widening its acceptance gate. PRE lateral capture now ends early by a live roll-dynamics distance, leaving room to roll wings level and prove the 0.75-second stability window. The accepted handoff occurred at 1,030 m remaining with -6.9 m lateral error, 3.3 degrees track error, 0.1 degree FPA error, 1.6 degrees bank, and 63.7 m/s carrier-relative speed.

This is not yet full Layer B acceptance. The three very-far cases above catch reliably in their recorded focused runs but still miss the proposed 300-second `PRE_LANDING` target. The complete 18-case dirty matrix and current-revision mixed/full-cycle suite also remain to be run before quoting a fleet-wide rate. The editor-only Godot validation exits 0 with no script or parse errors; forced early headless shutdown can still trigger the separate terrain-job/dummy-renderer teardown race described below.

## Implementation status (completed later on 2026-07-31)

The recovery integration described in this report has now been repaired far enough to produce repeatable end-to-end catches from the first two deterministic dirty cases:

- Normal-time `near_fast_cross` (3 km, 120 m/s, +35 degree bank, -8 m/s vertical speed) caught on its first recovery at 324.6 seconds with no wave-off or bolter. The recovery-to-final handoff occurred at 1,452 m after satisfying the unchanged lateral, track, FPA, bank, speed, and 0.75-second stability gates.
- The accelerated fixed-frame two-aircraft diagnostic ended `CAUGHT: 2`, with no wave-offs, bolters, crashes, timeouts, or teleport outcomes. Aircraft 2 held at queue position 1 for 321.9 seconds, received clearance after aircraft 1 caught, normalized its hold-exit pose, then caught after 276.5 seconds of active recovery time.

The implemented corrections cover RTB route provenance/progress recovery, carrier-relative recovery gates, physically attainable 3D arc tracking, preservation of authored primitive corner radii, pre-final rollout/stability, handoff ownership, a validated late-handoff deadline, bounded busy-deck holding, hold-exit normalization, and deterministic dirty/two-aircraft diagnostics.

This is strong evidence that the primary failure chain is fixed, but it is not yet the full acceptance result proposed below. Sixteen dirty cases, the 100-attempt final-controller regression, and the 20-run mixed combat/full-cycle suite remain to be executed before quoting a fleet-wide catch rate. Headless finite-suite shutdown also still triggers an existing dummy-renderer resource-leak backtrace after the harness has already emitted `COMPLETE`; that teardown defect is separate from the recorded landing outcomes.

## Executive summary

The carrier landing system is not failing as one indivisible controller. It is better understood as two systems joined at a handoff:

1. **Mission return and recovery setup** — leave combat, return to the carrier, obtain deck clearance, generate and follow a terrain-safe arrival, line up, slow down, and enter `PRE_LANDING` in a valid pose.
2. **Final landing** — fly the carrier-relative glideslope/centreline, reject an unsafe final, retry after a wave-off or bolter, and catch a wire.

The isolated test shows that the second system can work well when the first system supplies it with a controlled entry. Across the three recorded isolated-test logs examined here, there were **113 catches in 133 completed outcomes (85.0%)**, with 20 bolter outcomes and no recorded crashes or timeouts. The long run alone recorded **105 catches and 19 bolters in 124 outcomes (84.7%)**.

The recent mixed/full-cycle evidence is the opposite. In 12 selected recent full-cycle logs, including the three newest aligned-gate variants, there were **zero confirmed catches**. In the latest run, combat succeeded completely (4/4 ground targets and 2/2 enemy aircraft destroyed, both friendlies surviving), but:

- `Combat_Friendly_2` entered `RTB` and flew continuously away from the carrier, eventually exceeding 50 km carrier distance.
- `Combat_Friendly_1` repeatedly timed out on recovery-route progress, replanned, and made two automatic missed approaches without ever establishing a successful final.
- No successful `PRE_LANDING` stabilization or wire catch was recorded.
- The run ended at `t=1313.2` with `caught=0 requested=2 still_airborne=2`.

The strongest current conclusion is therefore:

> **The final landing controller is substantially proven under controlled inputs. The dominant current defect is the integration layer that must convert arbitrary post-combat aircraft states into those controlled inputs.**

This is not absolute proof that final approach has no defects. The isolated results were produced on the previous day's revisions, and the current recovery/handoff code has changed since then. A current-revision isolated regression run is still required.

## Evidence and limitations

### Isolated landing results

| Log | Recorded catches | Recorded bolters | Crashes | Timeouts | Catch rate among recorded outcomes |
|---|---:|---:|---:|---:|---:|
| `isolated_landing_visible_20260730_012932.log` | 6 | 1 | 0 | 0 | 85.7% |
| `isolated_landing_visible_restart_20260730_015407.log` | 105 | 19 | 0 | 0 | 84.7% |
| `isolated_landing_waveoff_visible_20260730_075126.log` | 2 | 0 | 0 | 0 | 100% |
| **Combined** | **113** | **20** | **0** | **0** | **85.0%** |

The first log had additional live work when logging stopped, and the long run had begun aircraft 125 after recording outcome 124. The table counts only explicit `[LandingTest] OUTCOME` records, not spawned aircraft. Bolters were terminal outcomes in those historical records; the current harness treats ordinary wave-offs and bolters as retry events.

These results are historical rather than a perfectly controlled A/B test. Source code evolved between the July 30 isolated runs and the July 31 mixed runs. They establish that the architecture and aircraft are capable of repeatable carrier catches, but they do not measure the current revision's isolated success rate.

### Recent full-cycle results

The following selected July 31 logs all contain zero confirmed `[CarrierCombatTest] ... LANDING caught` records:

- `recovery_isolation_full_visible_20260731_024343.log`
- `recovery_isolation_full_visible_repeat_20260731_071044.log`
- `recovery_isolation_full_visible_repeat_20260731_072938.log`
- `recovery_isolation_full_visible_repeat_20260731_075437.log`
- `recovery_isolation_full_visible_repeat_20260731_081019.log`
- `recovery_isolation_full_visible_repeat_20260731_083219.log`
- `recovery_isolation_full_visible_repeat_20260731_085110.log`
- `recovery_isolation_full_visible_repeat_20260731_091107.log`
- `recovery_boundary_full_visible_20260731_094604.log`
- `regular_full_cycle_lineup60_gunccip_20260731_140025.log`
- `regular_full_cycle_aligned_gates_20260731_153219.log`
- `regular_full_cycle_moving_alignment_gates_20260731_164545.log`

Several of the early runs lost the friendly flight before recovery. The later runs more usefully isolate the integration problem: surviving aircraft remain airborne until the recovery timeout but do not catch.

There are historical full-cycle examples of a successful catch in `recovery_steep_guard_full_cycle_20260729_141511_914.log` and `recovery_finite_segments_full_cycle_20260729_150105_739.log`. Both catches occurred after the test had already emitted its timeout `COMPLETE` line, which is additional evidence that the final controller can work from a good eventual setup, while also exposing a test-lifecycle/timing defect in those older runs.

## How the isolated landing system works

The isolated harness is `Scenario/LandingTestMode.gd` (scenario 5, profile `isolated_landing`). Its normal development mode deliberately removes most sources of uncertainty:

- It runs **one aircraft at a time** (`max_simultaneous = 1`).
- It spawns the aircraft **5–6 km from the carrier**, **450–900 m above the carrier**, at **90 m/s**, facing roughly toward the carrier with at most **25 degrees of yaw jitter**.
- It enforces at least **350 m AGL** at spawn.
- It removes bombs, reducing mass by roughly 300 kg for bomb-equipped aircraft.
- It disables dogfight, ground attack, health-triggered RTB, and fuel-triggered RTB.
- It marks the aircraft as a landing-test aircraft and explicitly starts it from a clean `SEARCH` state before calling `start_recovery()`.
- It suppresses normal air, enemy, and ground operations.
- It freezes the carrier and searches nearby positions/headings until it finds both a flat carrier footprint and a verified, terrain-clear landing corridor.
- It treats wave-offs and bolters as retryable events in current normal mode, allowing the same aircraft to request a fresh recovery route.

The most important point is that the isolated test does **not** merely test the last 100 metres. In normal mode it starts several kilometres away and calls the same `start_recovery()` path as the scenario. It therefore exercises return/arrival logic too, but from a narrow and deliberately favourable distribution of position, heading, altitude, speed, aircraft mass, terrain, task ownership, and traffic.

Once final owns the aircraft, `AIPilot.gd` uses a carrier-relative landing line and rolling flight-path-angle carrot. It compensates for measured carrier velocity, checks the live terrain corridor, monitors capture-cone geometry, and initiates a missed approach if the final becomes unsafe. A missed approach first restores safe energy and clearance, then calls `start_recovery()` again rather than steering directly back toward the touchdown point.

These are sound design features and are consistent with the isolated success rate:

- Final is carrier-relative rather than a stale world-space waypoint chase.
- Unsafe geometry causes a wave-off instead of a forced landing.
- A bolter is a retry, not an aircraft loss.
- The retry re-enters the full recovery planner.
- Wire engagement, rather than proximity to the deck, is the success criterion.

## How the current full-cycle recovery is intended to work

At the end of air combat, `CarrierCombatTestMode.gd`:

1. Marks every surviving friendly as recovery-requested.
2. Disables ground attack and restores threaded 3D heightmap routing.
3. Waits for the carrier's authored final corridor to be terrain-clear.
4. Freezes the carrier at that verified recovery pose.
5. Calls `start_recovery()` for each survivor.

`start_recovery()` hard-resets much combat and route state, including combat target, air task, formation guidance, outstanding route-job ownership, attack routes, waypoints, and weapon-solution state. Aircraft outside the local recovery radius first enter terrain-routed `RTB`; aircraft close enough request deck clearance and enter `RECOVERY_APPROACH` or `RECOVERY_HOLD`.

The current threaded arrival is designed as:

1. terrain-routed transit from the live aircraft position;
2. a continuous-curvature arrival turn;
3. three collinear carrier-axis alignment gates;
4. a `recovery_lineup` stabilization leg;
5. `PRE_LANDING` only after lateral, track, flight-path-angle, bank, and speed checks pass;
6. transfer to `LANDING` at the final handoff plane only after stable geometry is maintained;
7. otherwise an automatic wave-off and fresh recovery.

That separation is conceptually correct. The latest run shows the system failing before it completes steps 2–5 reliably.

## Confirmed current problems

### 1. RTB can fly directly away from the carrier

In the latest log, `Combat_Friendly_2` transitioned `SEARCH -> RTB` at `t=713.5`. Its carrier distance then grew monotonically from the local area to more than 50 km while it remained wings-level at about 82 m/s.

This is not a subtle final-approach tuning issue. It is a route ownership, coordinate-frame, or route-generation failure. The current `_state_rtb()` calls `_ensure_rtb_flight_plan()` and follows the route, so one of the following must be true:

- the RTB goal or generated route is in the wrong frame;
- a route segment is being transformed or rebased incorrectly after an origin shift;
- an asynchronous route result is stale despite the recovery reset serial;
- route progression is holding an incorrect segment while the final goal remains close enough to the expected carrier target that `_ensure_rtb_flight_plan()` does not rebuild it;
- navigation is following a bad maneuver carrot even though the stored final goal is correct.

The log does not yet distinguish these possibilities. Logging only the aircraft and carrier positions is insufficient; the active RTB waypoint, final goal, route-job serial, coordinate frame, and dot product toward the carrier must be captured.

### 2. Recovery route progress repeatedly times out and replans

`Combat_Friendly_1` repeatedly produced messages such as:

- `recovery progress timeout ... role=recovery_transit`
- `recovery progress timeout ... role=recovery_arrival`
- `recovery turn fallback: no terrain-clear pose solution`
- `recovery departure fallback: no terrain-clear pose solution`

The route shaper now successfully generates three arrival primitives in some plans, so the earlier multi-leg shaper rejection has been fixed. Nevertheless, the follower often reports that the aircraft has travelled far more than the remaining along-track distance without advancing. This points to a disagreement among:

- the route primitive's signed progress/completion rule;
- the dynamic maneuver carrot;
- the waypoint capture/projection logic;
- the actual aircraft turn response;
- the progress watchdog's estimate of an achievable turn period.

Repeated replanning is harmful even when each individual plan is valid. Every replan changes geometry, resets progress, and can prevent the aircraft from ever reaching the deterministic alignment gates.

### 3. Arrival turns are often too aggressive to produce a settled handoff

The latest telemetry repeatedly shows recovery banks near the configured 75-degree route limit. A 75-degree coordinated turn requires about 3.86 g merely to hold altitude; the controller's own telemetry often shows materially less available or measured load. The result can be large vertical-speed, angle-of-attack, and rollout transients.

Allowing 60–75 degree bank is useful and was explicitly desired for decisive turns. The problem is not the permission itself. The problem is planning a radius or timing that implicitly depends on that bank without confirming that the aircraft can supply the matching lift and still meet the next gate's altitude and speed. A turn may be horizontally reachable but not a viable three-dimensional approach setup.

### 4. Aircraft reach the handoff area without earning `PRE_LANDING`

The current entry gate is intentionally strict: approximately 45 m lateral error, 8 degrees track error, 12 degrees bank, plus flight-path-angle and speed limits. That is appropriate for protecting final approach. In the latest run, `Combat_Friendly_1` went directly from `RECOVERY_APPROACH` to `MISSED_APPROACH` twice, with about 34 degrees of bank at the recorded transition. This is evidence that the safety gate is doing its job, not that the gate itself is the primary failure.

The upstream route has not supplied the gate with a settled aircraft. The new aligned waypoints are therefore not yet validated by this run: the aircraft did not demonstrate orderly progression through them into `PRE_LANDING`.

### 5. Multi-aircraft recovery adds contention that the isolated test does not cover

The isolated test admits one aircraft at a time. Full-cycle recovery requests both survivors simultaneously. Only one can hold landing clearance, while the other must return, hold, and later obtain a route. This adds:

- clearance ownership and stale-holder checks;
- orbit/hold entry from arbitrary geometry;
- longer time for terrain or coordinate frames to change;
- a greater chance that one aircraft begins far outside the local recovery area;
- possible interactions with flight/formation task ownership.

This does not explain the runaway RTB by itself, but it is a major untested integration layer.

### 6. The current test reports completion while aircraft can remain alive indefinitely

The latest run ended on the recovery time budget with two friendlies still airborne. Older logs even recorded catches after a `COMPLETE` timeout line. The test timeout is useful operationally, but it means `COMPLETE` does not always correspond to a stable terminal simulation state. Statistical tooling must treat post-`COMPLETE` events carefully and the runner should stop or quarantine a completed process before counting the run.

## Why the isolated test works when the scenario does not

The isolated test collapses a high-dimensional problem into a narrow one:

| Input/condition | Isolated landing test | Mixed/full-cycle scenario |
|---|---|---|
| Initial position | 5–6 km around carrier | Wherever combat ends; potentially much farther away |
| Initial altitude | 450–900 m above carrier, min 350 m AGL | Arbitrary post-attack/dogfight altitude and terrain clearance |
| Initial speed | 90 m/s | Arbitrary combat energy |
| Initial heading | Roughly at carrier, ±25 degrees | Arbitrary attack/dogfight heading |
| Initial bank/load | Fresh, stable spawn | Can inherit combat bank, vertical speed, and load transient |
| Damage/fuel | Fresh aircraft; RTB triggers disabled | Mission survivor state |
| Payload | Bombs removed | Random operational loadout and expended/unexpended stores |
| Carrier | Frozen at a deliberately searched, verified pose | Moves during combat, then is frozen at the first verified recovery pose |
| Terrain corridor | Deterministically selected for flat footprint and clear final | Only the final is verified; arbitrary survivor-to-final transit still needs routing |
| Traffic | One aircraft | Up to two survivors and one clearance slot |
| Competing tasks | Combat and normal managers suppressed | Combat/formation/flight tasks must be invalidated at recovery boundary |
| Retry opportunity | Same aircraft can retry | Bounded by full-cycle recovery timeout and other integration failures |

This table explains the apparent contradiction. The isolated test reliably hands the recovery planner a reasonable state and gives it enough time to converge. The full scenario tests whether the system can manufacture that state from arbitrary mission conditions. That conversion is precisely what is failing.

## Ranked possible causes

The following are hypotheses, ranked by current evidence. Several may be active at once.

### High confidence

1. **RTB route/frame defect.** The monotonically increasing carrier distance while wings-level in `RTB` is direct evidence of incorrect guidance, not merely weak turning.
2. **Route-following/progress mismatch.** Repeated `along travelled > remaining`, progress timeouts, and replans show that route completion and actual flight do not agree.
3. **Arrival geometry demands a turn that does not leave a settled aircraft.** Repeated 75-degree banks and subsequent handoff rejection support this.
4. **The full-cycle failure occurs predominantly before final landing.** No `PRE_LANDING` success and repeated recovery/RTB failures support this strongly.

### Medium confidence

5. **Planner/follower three-dimensional capability mismatch.** Turn radii and terrain paths may be horizontally valid while requiring more lift, climb/descent authority, or rollout distance than the aircraft has at the commanded speed.
6. **Arrival primitive advancement is too brittle.** Arc signed-progress, projection, capture radius, and dynamic gate advancement may disagree after overshoot or large cross-track errors.
7. **The replan watchdog is too eager once the aircraft is off the planned primitive.** It may replace a recoverable plan before the aircraft can regain it, creating a replan loop.
8. **Two-aircraft clearance/hold sequencing exposes states absent from isolated testing.** The second aircraft's RTB path is the clearest example.

### Plausible but not yet demonstrated

9. **Residual asynchronous or flight-task ownership.** The recovery reset explicitly clears many owners, which lowers this probability, but a late callback or unreset controller state could still alter maneuver guidance.
10. **Origin-shift coordinate inconsistency.** There are existing guards and comments for prior origin-shift failures. The runaway RTB resembles a frame error, but the current log lacks the necessary waypoint/frame data to prove it.
11. **Fixed arrival geometry versus moving carrier-relative gates.** The direct alignment and lineup gates are updated with the live carrier, while terrain transit/arrival primitives remain world-space. This can create a discontinuity if the carrier moves during a long recovery. In the latest full-cycle run the carrier was frozen at recovery start, so this is unlikely to be the main cause of that particular failure, but it remains relevant outside the test harness.
12. **Damage, payload, or fuel changes handling enough to invalidate planner assumptions.** The mixed test aircraft are mission survivors and the isolated test removes bombs. The latest run does not include enough per-aircraft mass/damage/control-authority telemetry at recovery entry to quantify this.
13. **Terrain avoidance and recovery guidance may compete near ridges.** The full scenario must traverse arbitrary terrain, unlike the selected isolated corridor. A safety override can move the aircraft away from its primitive and trigger the watchdog even when both systems are individually reasonable.

## Recommended diagnostic changes

Before more controller tuning, add transition-focused telemetry. Continuous high-volume logs are less useful than one structured record at each ownership boundary.

### RTB record, every 5 seconds and on route change

Log:

- aircraft world position;
- carrier world position and measured velocity;
- active waypoint and final RTB goal;
- distance to waypoint and carrier;
- velocity dot product toward the waypoint and toward the carrier;
- route plan name, route-job serial, active index/role, and coordinate-frame/origin-shift epoch;
- route creation aircraft position and carrier position.

An invariant should immediately invalidate and rebuild RTB if carrier distance grows for 10–15 seconds while the commanded velocity-to-carrier dot product is negative.

### Recovery primitive record, on entry/advance/timeout

Log:

- primitive type, centre, radius, signed sweep, start/end positions;
- expected bank, g, vertical speed, and duration at planned speed;
- actual bank, available g, vertical speed, cross-track, signed angular progress, and carrot position;
- exact completion predicate values;
- watchdog expected period versus actual elapsed time;
- reason for fallback or rejection.

### Recovery handoff record

The current code already computes the correct values. Ensure every attempted `RECOVERY_APPROACH -> PRE_LANDING`, `PRE_LANDING -> LANDING`, and wave-off logs:

- remaining distance;
- lateral and vertical error;
- track and FPA error;
- bank;
- carrier-relative speed;
- stable time;
- active route index and role.

### Aircraft condition record at recovery order

Log mass, remaining stores, health, fuel, available engine power, stall speed, speed, bank, g, altitude AGL, vertical speed, current task, formation status, and outstanding route-job serial.

## Recommended fix sequence

1. **Fix runaway RTB first.** Add the waypoint/carrier invariant and reproduce with a far survivor. No landing tuning can compensate for an aircraft flying away from the recovery area.
2. **Create an isolated “dirty recovery entry” matrix.** Reuse scenario 5 but sample post-combat-like states: 3–20 km distance, ±180-degree heading, 60–120 m/s, ±60-degree bank, vertical speeds from −25 to +25 m/s, bombs retained/removed, and two-aircraft clearance contention. This bridges the current test gap without combat randomness.
3. **Make arrival feasibility explicitly three-dimensional.** Reject or enlarge a turn when required load exceeds available load, when predicted altitude error at rollout exceeds the next gate's envelope, or when insufficient straight distance remains to decelerate and level.
4. **Stabilize primitive advancement.** Unit-test arc completion and projection with overshoot, high cross-track, origin rebasing, and a moving/frozen carrier. The follower and watchdog must use the same progress coordinate.
5. **Prevent replan loops.** After a progress timeout, first command a short wings-level, terrain-safe reacquisition leg. Replan from that stabilized state rather than immediately generating another curved route from a large bank and cross-track error.
6. **Validate the aligned-gate concept in isolation.** Instrument explicit gate 1/2/3 crossings. Require a straight segment through all three, then check that `PRE_LANDING` is entered with low bank and acceptable track error.
7. **Only then tune final approach.** Re-run the current revision's isolated landing test. If its catch rate remains near the historical ~85%, keep final parameters stable while integration is repaired. If it regresses, separate final-controller work from arrival work.
8. **Add a two-aircraft recovery test.** One aircraft should hold without reserving an unusable deck slot, the first should catch or wave off, and the second should then receive clearance and recover.

## Proposed acceptance criteria

### Layer A: final controller

- At least 100 current-revision isolated attempts.
- At least 85% eventual catches.
- No terrain crashes.
- Wave-offs and bolters automatically retry.
- Every final either catches or exits through a finite missed-approach state.

### Layer B: dirty recovery entry

- At least 95% of live aircraft reach `PRE_LANDING` within 300 seconds from each sampled entry state.
- No aircraft exceeds 20 km carrier distance after an accepted recovery order unless its initial distance was already greater.
- No RTB aircraft increases carrier distance continuously for more than 15 seconds.
- No more than one route-progress replan per recovery in ordinary cases.

### Layer C: full cycle

- At least 20 completed runs with both combat and recovery enabled.
- Report catch rate per requested survivor, not merely per run.
- At least 80% eventual catches initially, then raise the target toward the isolated rate.
- Zero unexplained RTB departures and zero terrain crashes during recovery.
- Record separately: combat losses, recovery crashes, wave-offs, bolters, timeouts, and catches.

## Bottom line

The working isolated test is valuable evidence: it says the aircraft, carrier geometry, wire capture, final-path controller, and retry concept are fundamentally viable. The mixed scenario is failing because it asks a much harder upstream question—how to turn any post-combat survivor into a stable final-approach aircraft—and the current RTB/arrival/handoff integration does not yet do that reliably.

The next engineering effort should not loosen the final safety gates simply to create catches. The correct target is to make RTB and recovery routing consistently deliver the pose those gates already require.
