# Shared terrain maps and stable navigation coordinates — 2026-09-11

Implementation follow-up to [the full-scenario diagnosis](SCENARIO_TRANSITION_DIAGNOSIS_2026-09-11.md).
Aircraft handling, map resolution, terrain appearance, camera travel and the
floating-origin threshold are unchanged.

## Changes

- `TerrainMapCache` builds one relief/mobility image pair per navigation-data
  generation. It copies plain grid arrays on the main thread, rasterizes on one
  bounded worker, and creates the shared textures on the main thread. Cockpit
  radars and the tactical map only acquire references; drawing cannot trigger
  synchronous map generation. They show no terrain layer until the result is
  ready. Rebakes invalidate consumers and reject obsolete worker results;
  ordinary origin translations retain the existing pixels.
- `NavGraph` retains nodes and its spatial index in their original build frame.
  An origin shift updates a small offset under a separate mutex, without waiting
  for the path solver or rewriting the graph. Public queries convert input and
  output positions; segment clearance samples an immutable build-frame height
  grid. Cache files retain optional build-origin metadata and still load legacy
  version-12 caches.
- `NavPathScheduler` rejects queued, running and deferred world-coordinate
  results if their origin/grid generation changed. Callers receive their existing
  null/empty retry result, not an old-coordinate path. Carrier initial-placement
  cancellation now retries rather than prematurely declaring placement complete.
  Fixed-wing route jobs retain their existing serial/epoch provenance checks;
  they opt out of generic null replacement so an old callback cannot clear a
  newer request's active flag.
- Scheduler pool-task IDs are tracked and reclaimed only after completion during
  normal processing. Shutdown joins outstanding tasks before releasing scheduler
  callables. This follows Godot's requirement that every pool task be awaited to
  reclaim its resources: [WorkerThreadPool reference](https://docs.godotengine.org/en/4.5/classes/class_workerthreadpool.html).

## Scaling and limits

The former origin update scaled with graph size (186,953 nodes in the scenario)
and could wait hundreds of milliseconds for a worker. It now does constant-size
offset work. Other origin-shift subscribers still have their own costs, and
main-thread path/anchor queries can still wait on the solver mutex.

The stable navigation height snapshot adds about 6.26 MB at 1,565,001 cells.
Map generation temporarily copies two float grids (about 12.52 MB together at
that size), plus downsampling/image working storage. The two final 720x720 RGBA
layers contain at most 4.15 MB of pixels per CPU/GPU copy. Consumers share texture
resources; this is not an additional map pair per aircraft. There is only one
map worker, and completed/obsolete snapshots are released.

## Focused acceptance checks

- `TerrainMapCacheSmoketest`: exact relief/mobility pixel equality with the old
  builder; two radars and the tactical map share textures; shifts do not rebuild;
  rebakes replace textures and reject the stale generation.
- `NavGraphOriginFrameSmoketest`: positive and negative shifts preserve nodes,
  index, nearest-node/anchor answers and translated paths; a worker deliberately
  holds the solver mutex for 250 ms while the origin update remains independent;
  save/load after rebasing preserves paths; stale queued/running/deferred jobs
  are rejected, provenance-bearing jobs survive, and finished tasks are reclaimed.
- `NavGraphBuilderEquivalenceSmoketest`: existing 24-case graph/path comparison
  across both terrain profiles and multiple clearances.

## Rendered measurement method

The same real-scenario harness visits Aircraft 1, 5 and 11 twice, crosses roughly
9 km between targets, returns to the carrier, retargets mid-transfer and takes
player control. Only test-target flight motion is suspended. Normal background
operations and floating origin remain enabled; campaign autosaving is disabled.

Forward+ / Vulkan / RX 7800 XT, 60 FPS cap, 1280x720 window and 1920x1080 internal
viewport. Background activity and carrier placement vary, so cross-run maxima
are evidence for specific scoped improvements, not deterministic whole-game
speedup ratios. Captures include source hashes, phase boundaries, CPU scopes and
viewport timing; screenshots are taken outside measured windows.

The map-only intermediate capture, `user://transition_shared_map.json`, reduced
the first Aircraft 1 maximum frame from 1930.042 ms to 63.015 ms. It built one map
pair on the worker (2235.495 ms), with a 0.224 ms main-thread texture upload. Old
navigation-origin stalls remained, reaching 476.85 ms on a later transfer. All
handoff assertions passed; that intermediate process still crashed at teardown.

## Both fixes: rendered result

Artifact: `user://transition_shared_map_stable_nav.json` (matching `.log` and
phase PNGs). All recorded source hashes matched the finished files.

| Phase | p95 frame | Worst frame |
|---|---:|---:|
| Bridge idle | 17.38 ms | 18.25 ms |
| First Aircraft 1 | 17.98 ms | 64.59 ms |
| First Aircraft 5 | 18.86 ms | 81.43 ms |
| First Aircraft 11 | 20.32 ms | 130.77 ms |
| Repeat Aircraft 1 | 17.95 ms | 39.17 ms |
| Repeat Aircraft 5 | 18.32 ms | 98.39 ms |
| Repeat Aircraft 11 | 18.50 ms | 84.65 ms |
| Bridge returns | 17.87–18.24 ms | 31.00–42.78 ms |
| Rapid retarget | 17.89 ms | 25.66 ms |
| Player takeover | 17.83 ms | 19.67 ms |

One map pair was built (2346.920 ms on the worker), with a 0.235 ms texture upload.
First-cockpit handoff itself took 7.778 ms, including 0.586 ms panel checkout.
The remaining 64.59 ms first-use frame is not fully explained by those scopes;
do not label it all instrument allocation or GPU work.

The largest recorded whole-world shift was 8.958 ms, compared with 567.092 ms
in the baseline. `NavGraph.origin_shift` did not reach the 0.1 ms scope-event
capture threshold. The focused locked-solver test measured 0.013 ms; no node
rewrites or spatial-index rebuilds occur on completed-graph shifts.

The new worst frame (130.770 ms) contains 101.970 ms in `RockStream.rebuild`.
The next three worst frames also contain 64–65 ms rock rebuilds. This makes
budgeting/splitting rock population work the next supported optimization, not
another speculative change to the instrument panel. Main-view GPU time peaked
at 1.73 ms in this capture. Keep geometry and density intact while spreading
population work across frames, then repeat the same sequence.

Native viewport images were inspected for Aircraft 1, Aircraft 11 and the bridge:
the shared radar relief, cockpit, terrain and tactical consoles render. Aircraft
11's panel is upside down in both the baseline and new screenshots; that existing
mount/presentation issue was not changed by this optimization.

All five focused regressions passed with exit code 0: the three listed above,
`WorldMapMobilityTextureSmoketest`, and `FloatingOriginRigidBodySmoketest`.
Their ObjectDB leak warnings remain. Task cleanup removed the origin test's
previous shutdown crash, but it did **not** resolve the separate full-scenario
renderer shutdown problem.

The rendered sequence saved `COMPLETE`, no assertion failures, and both pooled
panels returned. The process then exited with code 1 / signal 11, following the
same null-material and leaked-RID teardown diagnostics seen before these fixes.
This is successful in-game transition verification, **not a clean process-exit
pass**. Campaign save timestamps and sizes remained unchanged.
