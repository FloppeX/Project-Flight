# Ground attack: commitment, threat priority and terrain survival

## Scope and plan

Temperament remains deferred in README's future-project list. This work concerns
the shared fixed-wing ground-attack pilot, initially measured with Aircraft 5.

1. Establish a diagnostic for actual guns, bombs and rockets, without legacy
   combat-harness control overrides. Record target choice, positioning/commit/
   egress time, release counts, target damage and aircraft/terrain outcomes.
2. Fix demonstrated broken handoffs before relaxing aiming or safety tolerances.
3. Select known, living hostile threats ahead of soft objectives, retaining
   distance/claim preferences within a threat tier and a stable committed target.
4. Validate repeat attacks and offset entry; introduce a collidable ridge beyond
   the target to test recovery. Terrain/pull-out authority must remain intact.
5. Expand to moving/firing targets and production terrain before claiming general
   reliability. Repeated blind attacks down an impossible corridor are not success.

## Diagnostic contract

`Tests/GroundAttackDiagnostic.tscn` spawns the production Aircraft 5 at 600 m,
100 m/s, 2.6 km south of two durable, non-firing ground targets. The depot is nearer
than a gun-emplacement-role target. Both keep health but count actual damage,
allowing several passes. The aircraft retains normal physical damage. Its authored
loadout contains a rocket pod, bomb rack and 15 mm gun; a command-line override
selects one attack weapon. Ammunition is unlimited for this diagnostic only.

No aircraft handling, attack control gains or weapon dispersion are overridden.
Skill is Experienced; dogfighting, carrier radius and RTB diversion are disabled.
Mission managers are suppressed so no new orders or unrelated units enter the
arena. Ground is physically collidable. Optional ridge: 260 m-high barrier,
3 km wide, 600-1,000 m beyond the gun emplacement. This is a deliberately severe
recovery obstacle, not a claim to represent the full procedural terrain system.

Use ordinary headless timing (`--max-fps 60`, NOT `--fixed-fps`) for acceptance:
some attack/weapon gates use wall-clock time. An accelerated simulation is not
equivalent for those gates. Finite runs write unique JSON reports under the Godot
user-data directory and check source hashes at each report. No scheduled task is
created or restarted.

Options: `--ground-weapon=Guns`, `--ground-weapon=Bomb`, or a quoted
`--ground-weapon=Rocket Pod`; `--ground-duration=180`; `--ground-offset=1400`;
`--ground-ridge`; `--ground-output=user://unique_name.json`.
`--ground-full-planner` retains the full corridor-planner comparison now that
direct interception is the production default.

## Findings and first correction

The V1 setup experiment is NOT an accepted baseline: it used accelerated timing,
and FlightDirector assigned a CAS mission inside the supposedly isolated test.
Its depot-first target selection was independently verified in V2.

The isolated, ordinary-time V2 gun and bomb runs each spent 180 seconds entirely
in ATTACK_POSITIONING, with zero commitments/releases and both aircraft alive.
The slow rocket trial was stopped after its retained partial observations; its
RUNNING artifact is not a completed 180-second result. Earlier V1 rocket runs
were likewise stopped; no logs were deleted.

A focused control probe showed only two `attack_approach` legs, no setup/target/
egress, and a nearly neutral roll command along an infinite route tangent even
after the final departure waypoint was behind the aircraft. The cause was not
simply excessive bank-angle caution:

- `_request_aircraft_heightmap_route` declines to enqueue when no path segment
  exists (e.g. no terrain navigation grid).
- `_set_ground_attack_flight_plan` had already built a complete terrain-checked
  fallback route, but replaced it with the temporary pending departure merely
  because heightmap pathfinding was enabled.
- No worker meant no callback to replace that temporary route. Replanning could
  repeat the same mistake indefinitely.

The pending departure now replaces the fallback only when a ground-attack worker
is actually active. The no-grid regression checks all three weapons retain setup,
target and egress (10 checks, zero failures). This is a real fallback bug, but the
isolated arena exposes it more directly than a main-world mission with a ready
navigation grid; it does not explain every historical live-game hesitation.

V3 measured this single correction before target-priority changes. The rocket run
completed 180 simulated seconds: two commitments, 12 rockets, 25 depot damage and
95 emplacement damage, aircraft alive. Gun/bomb runs reached firing and retain
90-second snapshots (39 gun rounds / two bomb drops), but reached the external
frame cap without a COMPLETE report. They are partial observations, not full
180-second outcomes. First commitments were 56.90 s for guns and 49.53 s for bombs.

Artifacts: `ground_v1_*` setup experiments, `ground_v2_*` isolated baseline,
`ground_control_probe*` route/control evidence, `ground_v3_*` fallback correction.
Existing headless resource/renderer cleanup warnings are not treated as proof of
clean shutdown. These tests validate state/physics, not rendered flight quality.

## Direct interception and threat-first targeting

The existing direct-intercept mode first committed around nine seconds in initial
on-axis probes; those exploratory probes were stopped, not completed full trials.
The adopted default uses a 35-degree commitment bank window (previous direct-mode
default: 15). Actual weapon-release limits are unchanged. Before commitment it
checks the existing physical recovery predictor and terrain corridor; rejection
begins a real egress rather than waiting indefinitely at the gate. The full
planner remains available as an exported alternative and has the fallback fix.

Known targets are ranked by threat tier first, then existing distance/claim
preferences. Emplacements, armed vehicles/controllers and carriers count as weapon
platforms; explicitly unarmed dummies do not. This is capability-based priority,
not a new omniscient threat sensor or a complete weapon-range/damage utility model.
Only the existing known/reported target lists are considered. Mid-setup retargeting,
when enabled, uses the same tier and rebuilds its route for the new target.

`AI/GroundTargetPriority.gd` is shared with `AirOps/Flight.gd`: otherwise automatic
CAS would still assign a nearer depot before the pilot could select a threat.
Flight assignment respects its existing area and unclaimed-target constraints,
excludes dead-but-retained targets and releases their claims. It no longer starts
fresh attacks during ATTACK_BREAK_OFF; the pilot owns physical pull-out and
reacquisition. Explicit player/mission target orders remain a separate authority.

## Six off-axis physical trials

`ground_v4_*`: 120 simulated seconds each, Aircraft 5 at 600 m and 100 m/s, initial
lateral offset 1,000 m, normal aircraft damage, durable non-firing targets. All six
reports COMPLETE and source-hash verified. Initial selection was the emplacement
in every case. The shared priority extraction/CAS guard followed these isolated
flight measurements and is covered by the final integration checks below.

| Weapon | Terrain | Commitments | Projectiles released | Target damage | Aircraft |
| --- | --- | ---: | ---: | ---: | --- |
| Guns | Flat | 1 | 25 | 120 | Alive |
| Guns | Ridge | 1 | 25 | 120 | Alive |
| Bombs | Flat | 2 | 4 | 0 | Alive |
| Bombs | Ridge | 1 | 2 | 381.40 | Alive |
| Rockets | Flat | 1 | 0 | 0 | Alive |
| Rockets | Ridge | 2 | 12 | 336.92 | Alive |

Guns first fired at 19.63/19.83 simulated seconds; bombs at 19.02/20.25. These are
not weapon hit percentages: blast damage differs from direct gun damage, targets
are immortal, and this matrix has a different target/entry from the early depot
baseline. Target damage is counted from actual damage calls, not predicted aim.

The result is better initial commitment, NOT reliable repeated destruction of
ground targets. Flat-ground rockets aborted with `dynamic_pull_up_no_accurate_rocket_ccip`;
flat-ground bombs released without damaging either target. Guns hit but did not
complete a second pass within 120 seconds. The ridge bomb run used a terrain waveoff
on the later approach instead of forcing the attack. No crashes occurred in this
small matrix, but it does not establish safety across terrain, aircraft or seeds.

Rocket trials needed 244/253 wall seconds for 120 simulated seconds under headless
load; mixed wall-clock/simulation-clock gates are therefore a remaining calibration
hazard even without accelerated `--fixed-fps`. Do not treat these timings as a
rendering-performance benchmark or compare cooldown-sensitive precision blindly.

A follow-up 65-degree commitment-window gun candidate (`ground_bank65_*`) remained
alive and scored 160/150 damage from 24 shots, but still only one commitment per
120 seconds on flat/ridge. It did not fix repeat-pass frequency and was NOT adopted.
The production window remains 35 degrees. The candidate scene preserves that
explicit experimental override for reproducibility.

## Verification and next iteration

Follow-up implementation and fresh impact/repeat-pass evidence:
[Ground attack repeat passes, September 10](GROUND_ATTACK_REPEAT_PASSES_2026-09-10.md).

Ground-attack plan/priority/CAS checks: 22, zero failures. They cover all three
weapons' no-grid fallback, threat-before-depot, friendly/dead/unknown exclusion,
dummy classification, a low steep approach failing recovery clearance, CAS claims
and no fresh assignment during pull-out. Pilot skill (60), visual contact (29),
evasion (62), pursuit (80), go-around response, route capture, terrain escape and
deck-footprint waveoff (136) also passed during this pass.

Next priorities:

1. Instrument actual bomb/rocket impact positions against their release predictions.
   Diagnose why a nominally accepted bomb solution misses the target and why the
   flat rocket entry reaches pull-out before a usable CCIP solution. Do not count
   indiscriminate early firing as effectiveness.
2. Correct repeat-intercept rollout/capture: the gun pilot crosses a potential
   attack heading while still banked, then misses the window and extends again.
   Merely raising the commitment bank threshold did not resolve it.
3. Separate attack/weapon simulation timers from wall-clock diagnostics before
   accelerated large matrices; profile rocket CCIP separately before optimization.
4. Add moving/firing threats, mission-manager-enabled integration and Aircraft 1/2
   coverage on production terrain. Shared defaults are not a claim of tested
   handling for every airframe.

No aerodynamic, landing-gear or damage-model changes were made in this pass.

Final shared-helper/CAS integration confirmation: `ground_final_Guns_ridge.json`,
60.02 simulated / 60.20 wall seconds, COMPLETE with all recorded hashes verified;
emplacement selected, 26 rounds released, 12 direct damage events / 120 damage,
aircraft alive. Final-source skill/visual/evasion/pursuit checks were rerun and
passed. All diagnostic processes started for this pass have finished or were
explicitly stopped as noted above; none is left monitoring in the background.
