# Navigation caching, staged spawning and sensor work — 2026-09-11

Follow-up to the rock/wheel optimization. Changes preserve terrain resolution,
vehicle counts, weapon cadence and flight physics. Test-only battle vehicles have
very high health and unlimited ammunition to sustain the measurement window.

## Implemented

### Exact navigation-grid cache

`Environment/NavigationGridCache.gd` stores the coarse heights, fine heights,
height variation, local maximum heights and the unquantized minimum. A SHA-256
fingerprint includes algorithm/source revisions, engine version, region/grid
settings, provider exports, initialized noise settings and the terrain's complete
world transform. Unknown providers are not cached. Cache reads validate format,
checksum, fingerprint, array types and dimensions before publishing readiness;
invalid/truncated entries fall back to a normal bake. Writes use a temporary file
and rename. A changed terrain/region during baking cannot write under its old key.

The default full-map payload occupies 58,376,990 bytes on disk per configuration.
Serialization/read decoding temporarily adds roughly one payload-sized buffer
alongside the normal grid arrays. Files live in `user://navigation_grids`, separate
from campaign saves. Different fingerprints retain separate files; automatic disk
eviction is not implemented. I/O is synchronous during loading, not during play.
Cold generation is still required for unseen/changed regions.

### Enemy platoon materialization

The existing `VIRTUAL` and `ACTIVE` enum values remain stable; `MATERIALIZING` is
added. One vehicle is created globally per rendered frame, so multiple nearby
platoons cannot each create their entire complement at once. Scene resources were
already loaded by the existing setup; the expensive activation is now staged.
Team and position are set before tree entry. Mission application and live-count
reconciliation happen after completion. Cancellation/tree exit stops pending
work, and the existing campaign-save blocker rejects non-virtual platoons.

One scene activation remains indivisible. A pathological spawn-position search
can still exceed the soft limit; this is not a hard millisecond guarantee.

### Sensor batches

AirOps candidate collection now deduplicates with instance IDs instead of repeated
linear array searches. `WorldUnitIndex` supplies an exact short-lived spatial
snapshot, including buildings/bases not covered by its persistent unit index.
Each serviced batch rebuilds positions from live nodes, avoiding stale-cell misses
after movement or floating-origin shifts. Exact spherical distance, team, range,
radar-enable and transport-state checks remain in force.

Observers are queued under a 1 ms soft budget, and no unfinished cycle is replaced.
Weak observer references and validated candidate references tolerate deletion.
The candidate roster still refreshes on the existing one-second cycle; observer
work can span several frames. The exhaustive query switch is retained for A/B
measurement. This changes scheduling, not pilot visual awareness or weapon aim.

### Camera handoff

Added separate attach, UI-enable, staging-release and camera-switch timing scopes.
The first instrument checkout was only 0.58 ms in the cold capture, so it was not
treated as the entire first-use hitch. Camera switching itself cost about 2.6 ms;
inspection found a recursive walk through the entire world to deactivate cameras.
It now clears only the current camera owned by the gameplay viewport, without
automatically selecting a fallback. Secondary viewport cameras remain untouched.
No camera route or cockpit art changes were made.

## Checks and measurements

`OptimizationSafetySmoketest` exercises exact cache round trips, invalidation,
corrupt-file fallback/replacement, indexed/exhaustive target equivalence, range
boundaries, freed references, multi-platoon staging and cancellation. In the
320-node/20-observer fixture, the complete synchronous sensor cycle averaged
9.760 ms exhaustive versus 1.040 ms indexed. The 1,000-node geometric comparison
returned exactly the same contacts using 1,115 in-range candidates rather than
100,000 observer/target combinations. These are synthetic scaling measurements.

Seven focused suites passed: `OptimizationSafetySmoketest`,
`TerrainBatchAndGraphSchedulingSmoketest`, `NavGraphOriginFrameSmoketest`,
`FlightDirectorAircraftTransitionSmoketest`, `CameraViewportIsolationSmoketest`,
`FlightDirectorCameraIdentitySmoketest` and `DefenseOpsSensorSmoketest`.
Each exited 0; focused tests retain ObjectDB exit warnings. The cache test also
covers an alternate terrain profile, disabled query grids, translated/rotated
terrain and origin shifting without changing the cached arrays.

The first rendered full scenario (`user://transition_cache_cold.json`) measured
40.574 s startup, including a 28.792 s navigation bake and 226.816 ms cache I/O.
Its platoon spawn slices peaked at 1.062 ms. Sensor batch maxima were 3.213 ms in
exhaustive mode versus 1.13 ms indexed/budgeted. The initial buggy battle fixture
did not produce sustained fire, so this capture is not accepted as a
combat comparison. It still recorded background combat and a
608 ms frame not explained by the captured script scopes; universal hitch removal
is not claimed. Its assertions completed before a renderer shutdown crash.

The subsequent warm capture loaded the same full grids in 204.489 ms; navigation
readiness completed in 302.755 ms and the loading screen closed at 11.660 s.
This is a measured repeat-load improvement, not a promise for every map/machine.
The warm capture's camera-switch scope fell below the 0.1 ms event threshold.
First-aircraft handoff was 5.858 ms and repeat handoff 1.231 ms, compared with
7.826/3.73 ms before removing the tree walk. First-cockpit worst frame was still
57.09 ms: native/render-side first-use work remains insufficiently explained.
All transition assertions passed; the overall warm test correctly failed its
sustained-fire assertions. Only its harness has changed since that capture;
recorded production source hashes still match.

### Separate combat finding

`user://transition_battle_gates.json` isolates the quiet buggy fixture. The first
five guns reported 90.08–90.95 degree aim error with valid targets, ammunition,
line of sight, allowed yaw arc and range. The shared `vehicle_lmg_turret.tscn`
declares a +X barrel axis, whereas `Turret.aim_at_point()` calculates yaw as though
the barrel faced +Z. Changing range or supplying unlimited ammunition did not
resolve it. This is a separately identified aiming defect; no production turret
behavior was changed during this optimization. Pickup and bus light-gun rigs also
reference that scene and warrant regression coverage when the aiming fix is made.
The sustained-fire benchmark now uses the APC's different modular turret rig.

### Sustained-fire capture

`user://transition_battle_final.json` completed all assertions with 32 APCs and
32 autonomous guns. Its two 15-second phases recorded 5,097 and 5,100 rounds
(physical plus cosmetic counters), and 7,829 damage across the fixture.
Both serviced 255 sensor observers: exhaustive candidate checks were 23,630,
versus 8,806 indexed (63% fewer). Captured sensor-batch maxima fell from 2.732 to
1.080 ms; overall AirOps scope maxima fell from 2.880 to 1.260 ms.

This is **not** a demonstrated whole-battle frame-rate improvement: p95 frame
times were 20.72 and 38.48 ms, and worst frames 69.88 and 67.07 ms. Background
aircraft/hangar activity changes over the sequential phases. Awaited hangar
settle scopes are elapsed wall time, not exclusive CPU cost. The battle-only
branch also bypassed the harness's post-startup frame cap; this was corrected
for a final capped rerun. Production code did not change between these captures.

`user://transition_battle_capped.json` confirms a 60 FPS cap in both phases and
passes all assertions: 5,092/5,093 rounds, 8,185.55 total damage, and 255 observer
updates in each phase. Candidate checks fell from 22,032 to 8,670 (61% fewer),
with captured sensor-batch peaks of 2.665/1.098 ms and AirOps peaks of
2.817/1.280 ms. Frame p95 was 26.39/28.83 ms, and maximum 65.53/79.63 ms:
the narrower sensor improvement is repeatable, but whole-frame improvement is
still not established. This rerun also encountered the shutdown crash below.
All 32 recorded source hashes match the final source files. Campaign save and
backup sizes/timestamps were unchanged; all benchmark processes are stopped.

The rendered capture wrote its complete results before a renderer teardown
crash (signal 11, null-material/leaked-RID diagnostics). The pre-existing exit
problem remains unresolved; successful assertions do not imply a clean exit.

### Next measurement candidates

- Remaining first-cockpit native/render-side work: switching and panel checkout
  do not account for the entire first-use frame.
- `MachineGunVirtualTracerManager.spawn_tracer()` rebuilds/uploads the complete
  cosmetic batch per new tracer, and the physics update does so again. At high
  gun counts this can scale with live tracers times new tracers per frame.
  Coalescing uploads is a candidate, not yet implemented or benchmarked; preserve
  damage-projectile cadence and handle interpolation/slot reuse deliberately.
- The independently reproduced LMG barrel-axis defect above deserves a gameplay
  fix with buggy, pickup and bus coverage.

## Reproduction

```powershell
& $godot --headless --path . --script res://Tests/OptimizationSafetySmoketest.gd -- --disable-campaign-autosave
& $godot --path . --windowed --max-fps 60 --script res://Tests/ScenarioTransitionPerformance.gd --quit-after 40000 -- --test-scenario=0 --disable-campaign-autosave --label=cache_warm --busy-battle
& $godot --path . --windowed --script res://Tests/ScenarioTransitionPerformance.gd --quit-after 20000 -- --test-scenario=0 --disable-campaign-autosave --label=battle_capped --busy-battle --battle-only
```

Use a unique label to preserve each capture. The existing transition harness
records source hashes, per-phase frame/viewport timings, CPU scopes, startup
milestones, battle shot counts and sensor counters. Campaign autosaving is disabled.
