# Terrain streaming and scenario startup

## Implemented scope

Preserve the existing terrain resolution, face colors/normals, shape, collision coverage, and procedural height API. No distant LOD, reduced collision radius, terrain cache, or navigation-resolution change in this slice.

- `LowPolyTerrain`: cap running plus completed/uninstalled chunk tasks at 8. Finalize ready chunks by current camera/stream-center priority instead of reverse launch order. Use a 2 ms soft main-thread installation/retirement budget during gameplay and an explicit 8 ms budget behind the scenario loading overlay. Retain count ceilings, transition prefetch, source-ring retention, and incremental unloading. A single indivisible operation may exceed the budget; it is not a hard frame-time limit.
- Reuse the already-generated, non-indexed vertex triples for collision instead of extracting faces back from the mesh. Regression compares the resulting collision and render triangles exactly.
- Join old workers before replacing noise/layout data during `rebuild()`.
- Add bounded aggregate timings for worker generation, completed-result waiting, mesh creation, collision creation, finalization, unload scheduling, and terrain process slices. Worker timers are elapsed durations, not exclusive CPU usage. Godot's eventual deferred destruction and GPU execution are not included in the unload-scheduling timer.
- `TerrainNavGrid`: replace each cell's square neighborhood scan with horizontal min/max windows and a vertical reduction. The ring buffer holds only `2r+1` rows (about 81 KiB for the default 2,084-column, radius-2 query grid), rather than another full-map intermediate grid. Same min/max, variation, invalid-cell, and boundary behavior; scratch buffers are released after analysis.
- Add per-stage navigation bake timings, graph cache-hit/build timings, and `[ScenarioLoading]` milestone / `[ScenarioLoadingReport]` records. Stage totals nest: graph initialization is inside navigation FINALIZING, and detailed chunk timings are inside terrain process/finalize timings. Do not add nested totals together.
- Loading waits for carrier initial placement and the currently requested terrain ring, not an empty queue left over from the previous camera position. Require three consecutive ready frames; recheck during the fade and restore the opaque overlay/loading budget if readiness is lost. Gameplay budget resumes before revealing the scene.

## Matched headless measurements

Godot 4.6.2, Open Canyons, seed 22551, gameplay height settings, 50 km x 50 km navigation extent. Grid bake: 1,565,001 coarse heights and 4,343,056 fine-query heights. These are isolated CPU/work measurements, not rendered FPS or total campaign loading-time promises.

| Grid stage | Before | After |
| --- | ---: | ---: |
| Coarse height sampling | 5.971 s | 6.040 s |
| Fine height sampling | 16.537 s | 16.367 s |
| Safety neighborhood analysis | 18.136 s | 4.380 s |
| Full isolated grid bake, wall clock | 40.735 s | 26.867 s |

Analysis improved approximately 76%; the isolated full bake improved approximately 34%. Sampling itself is unchanged. This is one matched before/after run; normal run-to-run variability applies.

Streaming benchmark: fixed camera sequence, radius 4, 28 x 28 quads/chunk, 36 m cells, collision enabled, initial fill, adjacent ring, 10 km jump and return. Preload-ahead disabled for deterministic ring placement; targets are explicitly refreshed at each leg.

| Leg | Before worst terrain slice | After worst terrain slice | Before/after fill time |
| --- | ---: | ---: | ---: |
| Initial | 9.174 ms | 3.613 ms | 1.524 / 1.498 s |
| Adjacent | 4.816 ms | 3.317 ms | 0.179 / 0.179 s |
| Jump | 6.137 ms | 3.832 ms | 1.393 / 1.427 s |
| Return | 7.129 ms | 3.382 ms | 1.262 / 1.248 s |

Outstanding task peak fell from 75 to 8. Fill throughput was broadly unchanged in this probe. Renderer/GPU/whole-frame costs remain unmeasured.

## Full scenario investigation

A normal full-size scenario probe (fixed region for repeatability, all normal startup systems enabled) found:

- Scene resource loading: 5.276 s; instantiation: 0.005 s; enter-tree/ready: 0.348 s.
- Navigation graph cache miss: **27.428 s**, 186,953 nodes, 3,425,126 directed edges. Graph setup runs synchronously inside the grid's completion signal.
- Grid stage totals: coarse 6.445 s, fine 16.227 s, analysis 4.326 s, finalization/listeners 27.568 s. Other gameplay work and scheduling also contribute to wall time.
- The initial probe revealed before terrain at the relocated carrier was ready. That observation prompted the current-view/placement readiness fix; its 67.224 s reveal time is therefore diagnostic, not a valid new loading-time target.
- That first full probe reached gameplay, then hit dummy-renderer null-material errors and a native crash at shutdown. Do not report it as a clean full-game pass. Focused tests exit normally apart from pre-existing material-property/ObjectDB warnings.

The final readiness-check probe, using the graph cache generated by the first probe, revealed at **41.022 s** with carrier placement complete, **81 loaded chunks**, **zero pending/in-flight chunks**, and the gameplay budget restored. First terrain fill was at 7.695 s, navigation ready at 36.202 s, and final-position terrain ready at 40.352 s. Graph cache load was 0.094 s. This is not a matched before/after full-scenario comparison: the cache state and random placements differ. Even with deferred scene cleanup, the full probe again crashed in dummy-renderer shutdown after recording its completed measurements. Rendered startup/exit still needs verification.

Focused validation passed: exact safety-grid comparison over 36 combinations (radii 1-4, rectangular/tiny maps, flat/random/impassable data); bounded worker queue; forced-expired-budget one-chunk progress; ready-chunk priority; exact render/collider triangle equality; stale-view readiness rejection; rebuild with outstanding jobs; loading/gameplay budget reset; existing camera handoff/source retention (destination delay 0.010 s); themed loading text/progress.

Existing `TerrainSummitProfileSmoketest` and `TerrainColorRegionsSmoketest` also passed; the summit test includes layered-route grade/height checks. The separate `LayeredMapProfileSmoketest` standalone entry point could not compile its preloaded `GameSession.gd` (`PilotRoster` identifier unavailable during preload); that diagnostic process was stopped, not counted as a pass. No GameSession/PilotRoster source changes were made here.

## Second pass: exact navigation-graph construction optimization

Implemented in `AI/NavGraph.gd` after the startup investigation above:

- Reuse clearance-map obstacle classification when selecting nodes instead of repeating all neighboring grade checks.
- Precompute the forward half of candidate grid offsets. Row-major node ordering means the other half was always rejected as already visited; accepted pairs retain their original order and distance checks.
- Replace per-node lists of `[neighbor, clearance]` arrays with three packed arrays of undirected pairs, degree counts, and a prefix-sum adjacency fill. The measured map no longer creates 3,425,126 nested edge arrays. This is an allocation-count reduction, not a measured peak-RAM claim.
- Reuse interpolation/grid coordinates during edge sampling and compute the grade limit once per edge instead of once per sample. Height interpolation, impassable-corner fallback, half-cell sample spacing, slope limits, and clearance minima are preserved.
- Add graph substage timings to startup reports. Graph initialization remains synchronous; reducing work does not yet remove its single-frame blocking behavior on a cache miss.

Matched full 50 km graph benchmark, Open Canyons seed 22551, cold graph construction in both runs (not cache loading):

| Graph stage | Before | After |
| --- | ---: | ---: |
| Clearance map | 3.607 s | 3.717 s |
| Node selection | 1.234 s | 0.085 s |
| Edge checking/collection | 22.639 s | 11.698 s |
| Adjacency packing | 1.542 s | 0.304 s |
| Whole build | **29.685 s** | **15.806 s** |

Approximately **47% less graph-build time**, or **13.9 s saved in this benchmark**. This is not a new matched end-to-end scenario loading measurement. A separate editor/game instance was left untouched during testing, so normal host-load variation applies.

All six serialized graph arrays have identical SHA-256 hashes before and after: nodes, node clearances, clearance grid, adjacency offsets, neighbor IDs/order, and edge clearances. Both builds contain 186,953 nodes and 3,425,126 directed edges. Cache format/version is intentionally unchanged because the output is identical.

Additional checks:

- `NavGraphBuilderEquivalenceSmoketest`: **PASS**, 24 synthetic cases across both profiles, 24/40/41.3 m grid spacing, fractional/negative origins, flat/gentle/threshold-grade terrain and impassable cliffs. Checks all arrays, actual paths at 0/80/120 m clearance, and cache save/load round-trip. Uses a frozen legacy builder fixture.
- `LayeredMapNavigationSmoketest`: **PASS**, 10 km map, 2,062 nodes, 53-point carrier route with 237 m height span, tactical-map vehicle/carrier layers. This integration check may use an existing graph cache; the equivalence suite and performance benchmark explicitly build graphs.
- Scoped `git diff --check`: clean. Headless tests exit successfully with ordinary ObjectDB warnings; some runs also report tuning-log files held by the existing game. No user-owned game/editor process was stopped.
- Full rendered startup/exit has not been rerun in this pass; the earlier dummy-renderer shutdown failure is not fixed by these graph changes.

Reproduction: `--script res://Tests/NavGraphPerformanceBench.gd -- --label=candidate` writes `user://navgraph_bench_candidate.json`, including every hash and stage duration. Run `--script res://Tests/NavGraphBuilderEquivalenceSmoketest.gd` for the legacy comparison and `--script res://Tests/LayeredMapNavigationSmoketest.gd` for integration.

## Third pass: batched heights and cooperative graph startup

Implemented:

- `LowPolyTerrain.sample_height_grid_rows()` snapshots the inverse transform, vertical offset, and noise setup once per row batch. It retains scalar-world Vector3 rounding, local transformation, bounds rejection, height calculation, quantization and vertical offset. Returns packed samples plus a full-precision minimum, so the bake's low-level threshold is unchanged.
- `TerrainNavGrid` uses that provider method when available, with the original scalar path retained for other providers and the `prefer_batch_height_sampling` diagnostic switch. Invalid samples still become IMPASSABLE. It does not interpolate, decimate, or cache approximate heights.
- `NavGraph` cold initialization uses cooperative versions of its existing builder, clearance flood and spatial-index loop. The normal budget is 8 ms, checked between rows or bounded groups of nodes/edges. It holds no pathfinding mutex across an await and never marks partial graph data ready. Synchronous builder calls remain available for deterministic tests.
- Bake invalidation cancels suspended graph work by generation; a cancelled coroutine cannot publish a result. Rebakes reconnect graph initialization. An origin shift during graph initialization cancels/restarts it in the shifted grid coordinates.
- Enemy-base placement now waits for graph readiness before anchor tests; disabling bases removes that pending callback. Save restoration and loading completion also explicitly wait for the graph. The height-grid completion signal no longer implies that graph construction finished synchronously.
- Timing reports include yield counts, maximum calculation-slice time and separate cache-write duration. Per-stage build timings exclude waits between frames.

Full-size Open Canyons measurements:

| Measurement | Result |
| --- | ---: |
| Batched coarse height sampling | 5.182 s |
| Batched fine height sampling | 14.012 s |
| Full isolated grid bake with batching | **23.386 s** |
| Fresh scalar-control full bake | **29.200 s** |
| Earlier scalar bake from the first pass | 26.867 s |
| Cooperative full graph, wall clock | **16.231 s** |
| Graph yields | **1,895** |
| Worst observed graph calculation slice | **10.965 ms** |

Batching saved roughly 3.5-5.8 s versus the scalar runs recorded here. The exact percentage is host-load dependent; these are component benchmarks, not rendered end-to-end loading measurements. All six full-sized graph hashes still match the original builder, including coarse-grid-derived heights, adjacency order and clearances.

The graph budget is soft, not a guarantee that the entire loading frame is under 8 ms. Individual units may overrun; cache reads/writes and allocation are not interruptible. Height sampling still runs in row batches (worst observed batch about 88 ms), scene resources and other startup listeners can also block. At a frame-rate cap, yielding adds scheduling delay: approximately 1,900 yields can occupy about 32 seconds at 60 FPS even though uncapped headless construction took 16 seconds. This pass trades that latency for responsiveness; do not advertise it as a universal total-loading-time reduction.

Validation:

- `TerrainBatchAndGraphSchedulingSmoketest`: PASS. Scalar/batch comparison at 9,976 positions across both profiles, quantized/unquantized heights, translated/rotated/nonuniformly scaled terrain and out-of-bounds samples; exact packed heights and full-precision minima match. Also checks synchronous/cooperative graph equivalence, multiple actual frame yields, cancellation, replacement publication, bake invalidation and loading readiness.
- `NavGraphBuilderEquivalenceSmoketest`: PASS, all 24 legacy-equivalence cases after introducing conditional yields.
- Full cooperative graph benchmark: same six SHA-256 hashes, 186,953 nodes and 3,425,126 directed edges.
- Layered navigation integration, terrain streaming budget, and themed loading text tests: PASS.
- Full rendered startup and end-to-end save restoration have not been rerun in this pass. The earlier headless full-scene shutdown failure remains an open limitation.

Commands: append `--cooperative=true --label=cooperative` to `NavGraphPerformanceBench.gd` user arguments; append `--scalar=true --bench-label=scalar_control` to the terrain nav benchmark to disable batching. The new scheduling regression is `--script res://Tests/TerrainBatchAndGraphSchedulingSmoketest.gd`.

## Remaining priorities

1. Measure capped/rendered startup latency and tune the cooperative budget. Consider immutable background work for expensive bake stages if the latency/responsiveness trade-off warrants it.
2. Investigate exact, versioned caching or independent worker snapshots for coarse/fine height baking. Any cache fingerprint must cover height-generating settings, profile revision, transform, grid resolution, and region; never reuse stale safety data. Merely increasing rows per frame does not remove the measured sampling work.
3. Capture a rendered flight and camera-transfer trace before making GPU/FPS claims. If needed, then evaluate bounded revisit caching and distant LOD with seam preservation.

## Reproduction

Run with the project's Godot console executable and `--headless --path .`:

```text
--script res://Tests/TerrainPerformanceBench.gd -- --bench-mode=nav --bench-label=candidate
--script res://Tests/TerrainPerformanceBench.gd -- --bench-mode=stream --bench-label=candidate
--script res://Tests/TerrainStreamingBudgetSmoketest.gd
res://tools/terrain_camera_handoff_smoketest.tscn
--script res://Tests/LoadingScreenNonsenseSmoketest.gd
--script res://Tests/ScenarioLoadingBench.gd -- --test-scenario=0
```

Benchmarks write `user://terrain_bench_<label>_<mode>.json` and `user://terrain_scenario_startup_<profile>.json`. Use unique labels/log filenames when preserving comparisons. Full-game autoloads also write their normal diagnostic logs and navigation cache; no saved scenario/menu configuration is changed by the harness.
