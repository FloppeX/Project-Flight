# Compact recovery control — 2026-09-18

The objective is reliable recovery with the shortest practical approach and total recovery time. This change does not lengthen the circuit. Reliability remains unfinished.

## Controller correction

The existing short-turn diagnostic selected three lift-vector safeguards by its `quick_recovery_turn_in` debug tag. The operational `compact_recovery_break` arc bypassed them:

- suppress the transient non-wing acceleration observer while resolving the compact turn;
- preserve the arc's compatible bank/load pair through the later generic path resolver;
- during roll-in, limit load using the actual lift direction so intended lateral load does not become excess vertical lift.

`AIPilot._uses_compact_recovery_vector_control()` now selects these rules from the actual recovery plan and arc primitive. Both production breaks and diagnostic turn-ins use them. Other flight phases keep their existing controllers. The short-turn diagnostic's separate minimum-bank setting remains diagnostic-only.

The 450 m radius, 2000 m turn-back point, 50-degree bank limit, 1000 m handoff deadline and wire geometry are unchanged. No production tuning of bank, approach length, capture tolerances or fuel was added.

## Operational tests

`CompactRecoverySortieProbe.gd` runs the normal launch/strike/RTB/wire/stow pipeline and adds controller telemetry. Godot 4.6.2 ran headless at fixed 60 Hz. Default weather remains enabled. Explicit optional CLI overrides are only for experiments.

| Run | Recall to wire | Missed approaches | Stowed health | Fuel | Strike damage |
| --- | ---: | ---: | ---: | ---: | ---: |
| Current-turn original-code baseline | No catch within 900 s | 7 | Not stowed | 18.36 | 70 |
| Vector correction, run 1 | 134.40 s | 0 | 100 | 74.44 | 428.74 |
| Vector correction, run 2 | 605.92 s | 3 | 100 | 24.88 | 0 |
| Vector correction, run 3 | 505.57 s | 3 | 100 | 55.07 | 151.16 |
| Experimental 60-degree bank | 141.50 s | 0 | 100 | 74.04 | 25 |

All three default candidate repeats caught a wire and stowed. Only two passed the complete strike mission: run 2 failed because it inflicted no target damage. It did **not** time out in recovery. Run 1 took 175.58 seconds from recall to stow; the other two took 640.07 and 546.57 seconds.

These are not matched trajectory replays. Launch/strike timing, damage, recovery entry and carrier movement differed. The prior turn also recorded a successful original-code recovery with five missed approaches. These small samples do not establish a population success rate or prove that this correction caused the operational difference.

## Controlled entry comparisons

`CompactRecoveryEntryProbe.gd` places Aircraft 5 at a documented downwind entry near the recorded carrier position, at 60 m/s, with calm weather. It uses the actual terrain, normal compact route, deck clearance, landing, wire and stow systems. It is a prepared entry test, not a launch/strike test. Initial carrier pose, aircraft pose and velocity match within each side's comparison. Physics scheduling and internal controller evolution are not checkpoint-restored.

| Prepared entry | Result within 240 s | Entry to wire | Observation |
| --- | --- | ---: | --- |
| Right, original vector behavior, 50 degrees | Caught and stowed | 87.93 s | No sampled missed approach |
| Right, corrected vector behavior, 50 degrees | Caught and stowed | 88.17 s | A missed-approach state occurred shortly before catch |
| Right, corrected, 60-degree experiment | No catch | — | Two missed approaches |
| Left, corrected, existing 1000 m deadline | No catch | — | Terrain-raised ingress, replan, later landing rejection |
| Left, corrected, experimental 600 m deadline | No catch | — | Later handoff did not produce a recovery |

The paired right-side test shows essentially unchanged recovery time, not a proven speed gain. The 60-degree bank and 600 m deadline experiments are **not** promoted to production.

The forced left-side route required about 570 m of ingress elevation and 67 m of circuit elevation. It initially stalled in route progress and replanned to the other side. This is therefore not a clean mirrored arc-only comparison: terrain and ingress feasibility matter. Normal route selection can choose the other side; the fixture deliberately fixes the initial side to expose this case.

The stock operational `recovery_press_mode_enabled` fallback remained enabled. Logs show `press_commit` transfers with `normal_gate_passed=false`, including the first successful operational candidate. No new permissive override was added, but these catches must not be presented as proof of the strict settled handoff. Wire capture and stow were physically observed. The late missed-approach/wire-catch transition also remains an ownership issue to investigate.

## Focused checks and next work

- `CompactRecoveryVectorSmoketest`: PASS. For both turn directions, a 2 G vector at a requested 60-degree bank delivers approximately 0.993 vertical G while actual bank is 45 degrees, independently of the leg debug label. Straight and combat legs do not select the compact-arc rule.
- `RecoveryClimbAuthorityProbe`: PASS.
- `RecoveryTerrainEscapeSmoketest`: PASS.
- No SCRIPT ERROR in the completed final runs. Existing headless rendering/material and shutdown warnings remain.

Next work should isolate the terrain-raised ingress and centerline stabilization, explicitly record strict versus press handoffs, and measure time to the first usable landing opportunity. Repeating a rejected geometry or merely allowing a later unstable commitment is not an established solution. No fleet-wide, crosswind or moving-carrier reliability claim follows from these tests.

## Evidence

`logs/compact_recovery_comparison.json` summarizes the first nine completed trials. The named runs have `.log`, `.jsonl`, and `_status.json` artifacts in `logs/`; the later deadline trial is `compact_entry_left600`. The production trace includes actual glide-path error, entry assessment, lift/load state, terrain climb constraints and full route legs. `Tests/Fixtures/LegacyCompactRecoveryPilot.gd` supplies the earlier ordinary compact-arc behavior for controlled comparisons.

## Arrival selection follow-up

`CompactRecoveryArrival.gd` assesses candidate legs; `AIPilot` builds six candidates (both sides, each with a heading-dependent entry and the near/far downwind entry limits). It retains terrain clearance checks, rejects unreachable climb/descent legs and insufficient braking distance before the break, and ranks remaining candidates by estimated route time plus the turns into downwind. The climb calculation includes braking travel time for fast entries. Heading uses velocity relative to the carrier. Equal scores retain the existing preferred side. Candidate evaluation does not install a plan or reset clearance/controller history; only the winner is installed. With no acceptable compact candidate, the existing recovery staging/reacquisition path remains responsible for another opportunity.

The original difficult left join demanded about 570 m of climb in a 450 m leg: about 41 seconds at the configured climb limit, against 7.5 seconds at approach speed. The new assessment rejects that demand. It does not increase circuit length, bank limits or handoff tolerances.

Initial selection runs, before the final fast-entry timing and carrier-relative heading refinements:

| Scenario | Entry/recall to wire | Entry/recall to stow | Result |
| --- | ---: | ---: | --- |
| Prepared left, normal selector | 177.15 s | 218.12 s | Caught and stowed, health 100 |
| Prepared right, normal selector | 87.62 s | 128.88 s | Caught and stowed, health 100 |
| Full strike sortie | 124.58 s | 165.67 s | Mission PASS, 172.58 target damage, health 100 |

The earlier forced-left fixture failed to catch within 240 seconds. This comparison changes selection as well as geometry; it is not a matched replay of the old production selector. The right entry remains approximately as short as before. The left run still sampled MISSED_APPROACH immediately before capture. The sortie used the existing press handoff with `normal_gate_passed=false`, so operational recovery does not demonstrate strict handoff success.

The ranking is a heuristic over six candidates, not a globally shortest or dynamically guaranteed trajectory. Join turns are estimated rather than constructed as terrain-checked curved paths; wind, acceleration and actual climb capability can change the result. Existing flight-time safety controllers remain necessary. Fleet-wide and crosswind validation is outstanding.

Focused checks: `CompactArrivalPlanningSmoketest`, `CompactRecoveryVectorSmoketest`, and `RecoveryClimbAuthorityProbe` PASS. Arrival tests cover impossible climbs/descents, fast-arrival braking/climb time, heading cost, opposite-side selection, stable ties, and no installation when every candidate is rejected. Evidence is under `logs/arrival_select_*` and `logs/compact_arrival_planning_smoke.log`.

Final-code repeats after the fast-entry timing/carrier-relative heading refinements:

- `arrival_select_left_final`: wire 176.17 s, stow 216.95 s after entry/recall; health 100, fuel 87.53.
- `arrival_select_sortie_final`: wire 138.55 s, stow 173.40 s after entry/recall; health 100, fuel 73.07. Full mission PASS; target damage 95.00.

Both final repeats still used press handoffs. The left repeat retained the late MISSED_APPROACH/catch overlap. No SCRIPT ERROR occurred in these final runs. Existing headless material/rendering and cleanup warnings remain. `logs/compact_arrival_comparison.json` records all five arrival-selection runs. Next work is strict centerline/bank stabilization and ownership of the wave-off versus wire-catch transition, followed by broader weather/fleet repeats.

## Final-line control and catch ownership follow-up

The actual prepared right entry leaves the compact arc about 250 m off the centreline. The existing wire-oriented lateral solver uses a short correction horizon; with that large entry error it saturates acceleration toward the line and reverses late. PRE_LANDING now uses a critically damped line-capture command, including predicted position over actuator response time. LANDING retains its existing wire solver. Bank and rudder consume the same commanded lateral acceleration; the existing roll controller, turn radius, straight length and acceptance gates are unchanged. This is earlier lateral braking, not proof that the aircraft will satisfy the final handoff boundary.

`ArrestingCable` now notifies the pilot of confirmed engagement before emitting the signal that lets FlightDeckManager disable controls. An AI recovery pilot clears the go-around flag and stored escape throttle and moves to LANDING. Physics also reconciles engagement before yielding to deck-owned controls. Both internal and external wave-off paths reject attempts to override an established arrest. Uncaught aircraft retain their escape behavior, and passive player observers do not enter autopilot landing. A predictive wave-off before the physical catch is still possible; capture now supersedes it correctly.

| Prepared entry | Entry to wire | Entry to stow | Health | Final recorded pilot state |
| --- | ---: | ---: | ---: | --- |
| Right, damped capture | 89.08 s | 130.40 s | 100 | LANDING |
| Left, damped capture | 177.55 s | 219.17 s | 100 | LANDING |

Right-side handoff track error was 8.9 degrees and bank 10.7 degrees, versus approximately 18 and 22 degrees in the earlier prepared right run. However lateral error was -46 m and vertical error +49 m; the aircraft still required press handoff. Left-side handoff also required press, with 9.4 degrees track error, 16.3 degrees bank and +52 m vertical error. These are improved lateral-motion observations, not strict-gate passes or a reliability rate. Recovery time remains approximately unchanged.

Rejected experiments shortened the wire solver's target horizon and substituted a different roll controller. Both prepared sides failed to catch within the test window; retaining the original roll controller while shortening the horizon also failed on the right. Those experimental changes are not retained. Their logs are `handoff_left`, `handoff_right`, and `handoff_right_horizon`; retained-command runs are `handoff_*_damped`.

`RecoveryCatchOwnershipSmoketest` passes uncaught escape preservation, disabled-control capture, late internal/external wave-offs, idempotence, passive-player exclusion, and real cable notification ordering before deck subscribers. `PreLandingLateralSmoketest` passes early braking, mirror symmetry, zero correction when settled, and convergence in a simple lagged lateral model; that model is not a full aircraft simulation. `LandingSightSmoketest` passes existing final guidance checks. Runtime evidence and summaries remain in `logs/`.

Full mission `handoff_sortie_damped`: mission PASS, 478.29 target damage; recall-to-wire 291.20 s, recall-to-stow 333.05 s; 2 sampled missed-approach transition(s); stowed at health 100 with fuel 50.76 and pilot state LANDING. It required a retry and press handoffs. Its first arrival was much farther off-axis (-239 m) than the prepared entries; this run does not establish a speed gain over the earlier unmatched sortie. No SCRIPT ERROR appeared in retained-command runtime runs. Existing headless renderer/material and shutdown warnings remain. `logs/handoff_recovery_comparison.json` summarizes the retained runs.

Remaining diagnosis: the compact arc exits wide, spending much of the short straight on lateral acquisition, while vertical error also remains above the strict gate. Fixing that upstream exit is needed before claiming consistently short, strictly stabilized landings; acceptance limits have not been relaxed.
