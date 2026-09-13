# Dogfight escape commitment and false terrain crashes

Follow-up to `DOGFIGHT_SEPARATION_AND_CAPTURE_2026-09-09.md`. This pass measures
actual motion through a 10 Hz observer and fixes two control issues plus a shared
aircraft terrain-safety defect. It does not retune aircraft physics or enable
evasive combat behavior. The proposed defensive slice is in
`EVASIVE_FLIGHT_DESIGN_2026-09-09.md`.

## Findings and implementation

### An aircraft overhead could become "ground"

The fallback ground-height ray begins 50 m above the aircraft, points down, and
previously excluded only the querying aircraft. It could hit another aircraft
overhead, return that aircraft's surface height as ground, and make
`_enforce_above_terrain` destroy a healthy aircraft in midair. The same raw probe
was used for terrain impact normals.

Both paths now use a shared bounded ray helper that skips aircraft bodies and
their child collision bodies, while retaining terrain, runway and carrier hits.
Normal physical aircraft collisions remain enabled. The preferred Terrain3D
height API is unchanged; the defect specifically concerns the fallback path,
including these terrain-less duel scenes. This is not evidence that every past
carrier or midair loss had this cause.

The regression instantiates real aircraft 5 and 3, vertically separated by 20 m.
It proves that the old raw ray hits the upper aircraft and returns "ground" above
the lower one. The fixed query finds actual ground, preserves full health,
retains raised-deck detection and real below-ground detection, and returns
unknown when only airborne traffic exists. All 10 checks pass.

Ordinary fallback queries still use one ray. Overlapping aircraft can require
additional rays, capped at 16; the height API fast path remains untouched. This
is a scaling description, not a measured frame-time improvement.

### Escape release could undo the maneuver while still closing

The old release rule used elapsed commitment and distance alone. In a traced
parallel pass, a pair changed from opposite +90/-90 m escape requests to the
opposite vertical choices while range was still closing through approximately
295, 205, 117 and 34 m. Rebuilding the break was undoing established separation.

Release now also requires opening relative motion and an established own
velocity direction along the escape. The regression fixture itself was fixed:
its previous initial encounter never triggered avoidance, so comparisons of
zero waypoints could falsely pass the commitment test.

Banked encounters requiring a reversal now receive extra prediction time, capped
at six seconds. Near-level opening passes retain the three-second horizon. The
35 deg/s roll estimate is deliberately approximate, not an airframe-calibrated
performance model. A longer horizon alone did not solve the stress case and was
not treated as sufficient evidence of success.

## Final normal-harness results

Normal health and ammunition, production pilots, 60 Hz physics, headless
`--fixed-fps 60`, 240-second round limit. All four reports are COMPLETE and all ten
recorded input hashes match, including the newly tracked shared aircraft script.

| Start | Hits / shots A | Hits / shots B | Duration | Min center separation | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Aircraft 5 vs 3 head-on | 7 / 12 | 17 / 30 | 18.88 s | 401.2 m | Aircraft 5 gun victory |
| 5 vs 5 close parallel, seed 20260909 | 0 / 0 | 0 / 0 | 240 s | 23.5 m | Both at full health; timeout |
| 5 vs 5 close parallel, seed 20260910 | 0 / 0 | 0 / 0 | 240 s | 23.5 m | Both at full health; timeout |
| 5 vs 3 perpendicular, seed 20260911 | 0 / 0 | 2 / 2 | 240 s | 85.6 m | Both alive; hull health 100 / 60 |

Before the ground fix, three normal close-parallel runs ended at 113.17 seconds
with zero shots and sudden destruction, with the two aircraft approximately
50 m apart vertically. The focused regression establishes the false-ground
mechanism; the final stress runs no longer suffer that death. They still have
close passes and fail to obtain a firing solution. Surviving a timeout is not a
gunnery victory, and two identical seeded trajectories are not independent
statistical evidence.

Instrumentation affects trajectories: the earlier audit subclass produced a
107.4-second gun victory in a close-parallel run while the normal harness suffered
the false-ground loss. Keep observer mode fixed when comparing tuning; do not
pool those as interchangeable deterministic trials.

The final 10 Hz audit subclass (also fixed 60 FPS) produced a 121.40-second
Aircraft 3 gun victory in the perpendicular case: B scored 14 hits from 22 shots,
A fired none, minimum center separation 89.6 m. The audited parallel case still
timed out without shots. Each pilot had about 54 seconds of latched escape and
100 seconds with the `lost_visual_contact` firing block; remaining sampled
blocks were principally aim angle and range. This is not an escape held forever,
and it points to post-break reacquisition/capture as the next control problem.
Both audit reports are COMPLETE with all 11 hashes matching, including the
observer script. Audit traces are debug measurements, never pilot inputs.

90-second fixed-60-FPS unlimited-health tracking cases before the harness startup
correction described below:

| Case | Hits / shots | Precision time | First acquisition |
| --- | ---: | ---: | ---: |
| Tail chase | 594 / 595 | 89.03 s | 0.98 s |
| Gentle left | 510 / 513 | 88.98 s | 1.03 s |
| Crossing left | 81 / 84 | 17.48 s | 71.93 s |
| Crossing right | 120 / 128 | 23.47 s | 65.93 s |

All four reports are COMPLETE, input hashes verified, and no case is invalid.
Tracking remains effective, but these counts are not identical to the previous
benchmarks. Autocannon cooldown currently advances in `_process` while pilot
fire requests run on physics ticks, so render/idle cadence is a comparison
variable even headlessly. Do not interpret raw shot totals across launch modes
as an aim improvement or regression without a cadence-matched control.

### Tracking harness initialization race

A subsequent ordinary-time tail control produced zero shots and no acquisition.
The harness waited for physics frames, while `Aircraft._ready` resumes on an idle
frame to bind its modules and controls. Measurement could therefore race aircraft
initialization. The harness now waits two idle frames as well as two physics
frames before finalizing and resetting the trial. This changes the test setup,
not the production flight controller.

The short ordinary-time control then acquired at 0.98 seconds and scored 69/70
hits/shots over ten seconds, with 9.02 seconds of precise tracking. The fixed-frame
control acquired at the same time and scored 61/63. Thus the previous no-acquisition
run is not a valid steady-state comparison, and cadence still influences firing
totals. The output now records launch arguments, physics frequency, time scale and
gun RPM to make these distinctions explicit. The gun cooldown itself was not changed.

Final initialized harness, ordinary-time headless execution, 90 seconds per case:

| Case | Hits / shots | Precision time | First acquisition |
| --- | ---: | ---: | ---: |
| Tail chase | 667 / 669 | 89.03 s | 0.98 s |
| Gentle left | 580 / 585 | 89.03 s | 0.98 s |
| Crossing left | 93 / 96 | 17.33 s | 72.03 s |
| Crossing right | 135 / 142 | 23.80 s | 65.53 s |

All four are COMPLETE, hash-verified and valid. This supports effective sustained
precision in the simple tracking cases, not solved cross-target acquisition or
frame-independent weapon cadence. Crossing acquisition remains slow. All owned
tests finished; no ongoing test process is required to obtain these results.

## Regression checks

- Dogfight pursuit: 80 checks, zero failures.
- Visual contact: 23 checks, zero failures.
- Ground probe traffic: 10 checks, zero failures.
- Gunnery tracking baseline fixture: PASS; 1,000 immortal-target hits and all
  190 authored dogfight settings preserved.
- Carrier launch terrain safety and launch reposition: PASS.
- Collision shape lookup: 15 models, 30 cases, 264 gear and 124 body contacts,
  zero failures.
- Carrier contact damage zone: 9 models, 54 contacts, zero failures.
- Go-around response: PASS.
- Recovery route capture, recovery terrain escape and deck-footprint waveoff
  (136 checks) passed after the AI changes, before the shared ground-ray change.

Full-airframe headless runs still emit existing dummy-renderer/material and
resource-cleanup errors at shutdown; assertions passing does not imply a clean
shutdown. No full carrier recovery batch or visible flight was run in this pass.

## Artifacts and next step

Artifacts are under
`C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier/`:

- `traffic_ground_fix_{merge,parallel_a,parallel_b,crossing}.log[.json]`
- `traffic_ground_fix_tracking_*.json` for the earlier timing comparison runs.
- `tracking_startup_probe_*.json` and `initialized_tracking_*.json` for corrected
  harness startup controls and ordinary-time precision regressions.
- `traffic_ground_fix_audit_*.log[.json/.trace.json]` for final achieved-motion traces.
- `separation_audit_base_*`, `separation_reversal_*` and `separation_commit_*`
  preserve intermediate experiments, not final acceptance results.

Next, use the surviving parallel/crossing traces to distinguish visual loss,
escape commitment and ineffective re-interception before changing capture
guidance again. Do not count ordinary nearby opponents as automatic evasive
threats: permanent defensive turning would reinforce the stalemate. The proposed
evasive slice starts with credible observed danger or source-aware damage,
reaction delay, a committed break and an energy-aware extension, followed by
reacquisition. No GA or new force overrides yet.
