# Rock population and shared ground-wheel support — 2026-09-11

Implementation follow-up to [the diagnostic audit](ROCK_AND_GROUND_WHEEL_DIAGNOSIS_2026-09-11.md).
Aircraft/helicopter aerodynamics and landing gear are unchanged.

## Rock population

- Cell keys and random/noise coordinates retain their original frame across world
  shifts. The scene hierarchy moves the existing local rock transforms with the
  terrain. Origin notification itself only updates an offset.
- Missing cells are queued near-first and evaluated under a 2 ms soft main-thread
  budget. Retargeting replaces obsolete queued work; navigation rebakes invalidate
  the old population. Occupied and empty cells both remain cached.
- Collision misses remain pending rather than displaying a permanently misplaced
  procedural-height rock. Bounded retries check chunk availability and finalize
  placement when terrain collision becomes available. Collision queries stay on
  the main thread; no worker accesses physics space.
- One capacity-bounded MultiMesh is reused. Its visible count changes as valid
  candidates finish. The temporary imported rock hierarchy is freed after taking
  its mesh reference. Physics interpolation is disabled for this static batch so
  repacked slots cannot interpolate between unrelated rock positions.

Density, seed, support-ring tests, geometry and draw radius are retained. New
areas fill gradually rather than blocking until every candidate is complete.
Enumeration, one candidate, and the final upload can overshoot the soft budget;
this is not a hard real-time guarantee. Pending collision retries are bounded by
the current footprint. With the default 500 m effective radius and 25 m cells,
about 1264 cells are retained, plus a 2000-instance transform capacity (about
96 KB of transform data before engine overhead).

## Shared ground support

`GroundVehicle/WheelSupport.gd` replaces duplicated friendly/enemy support math
and the old unreachable solver copies. Existing vehicle-side fields/wrappers
remain compatible with the movement and deployment/retrieval code.

- Contact offsets compose the actual authored wheel basis and marker position.
  Steering multiplies the rest basis instead of overwriting mirrored mount yaw.
- Four/six contact rays now serve both chassis support and individual wheels,
  replacing eight/ten separate corner-plus-wheel rays. A fitted support plane
  determines the chassis pose; actual hit planes determine individual travel.
- Suspension travel is solved along local Y against the hit plane, reprojected
  after chassis integration, and capped at 0.60 m compression / 0.65 m extension.
  These are exported ground-vehicle settings, not aircraft suspension values.
- Cached moving-body contacts retain body-local points/normals; carrier operations
  use physical-only support and update moving contacts between probe refreshes.
  Lost support does not invent a deck beneath the vehicle.
- Ordinary detailed range is 250 m, with one ray per wheel every other simulation
  update. Distant vehicles use three contact samples every 0.20 seconds and retain
  a sloped support plane rather than being forced level. Spring integration remains
  separate from query frequency, with substeps for coarse simulation ticks. Narrow
  camera FOV scales up the detailed range; target focus also requests detail.
- The 450 m wheel-mesh cutoff is removed by default. Imported mesh LOD and shadow
  distance policies remain. Target-camera focus also overrides an explicitly set
  wheel cutoff while the target is being inspected.

This improves correctness and reduces query counts, but adds plane fitting and
contact projection. It is not a claim that every nearby support update is faster
than the previous incorrect math. Distant detail and mesh visibility are now
independent decisions.

## Focused coverage

- `RockStreamIncrementalSmoketest`: unchanged cells, negative cache, ordinary
  hillside acceptance and cliff rejection.
- `RockPopulationBudgetSmoketest`: multi-frame cold population, identical cached
  transforms after rebasing, retained MultiMesh, bounded retarget queues, rebake
  cancellation and late collision finalization.
- `WheelSupportSmoketest`: all five ground scenes, authored contacts, mirrored
  steering, tilted-plane projection isolated from travel caps, bounded travel,
  moving support, 10-degree collision ramp settling, step stability, coarse query
  count, lost support and origin invalidation.
- Existing `vehicle_performance_lod_smoketest`: movement scheduling, offscreen
  processing, target/dust policies and reversible mesh LOD.

The focused rock run populated 1264 candidates over 32 slices; its largest slice
was 2.175 ms. All five projection tests were within 0.000008 m with the travel cap
temporarily raised to isolate geometry, then passed the normal travel-bound
checks. All five vehicles settled within 0.001 degree of the 10-degree test ramp.
These are fixtures, not guarantees for arbitrary terrain or driving conditions.

## Rendered verification

Two full scenario transition captures completed with no assertion failures and
process exit code 0: `user://transition_rock_wheel_shared.json` and
`user://transition_rock_wheel_final.json`. The final capture includes the static
rock interpolation and zoom-detail fixes, and all 26 recorded source SHA-256
hashes match the checked files. The engine rendered at the saved 1920 x 1080
setting with a 60 FPS cap. Campaign save sizes/timestamps remained unchanged.

| Measurement | Previous baseline | First implementation run | Final run |
|---|---:|---:|---:|
| Largest rock work slice | 101.970 ms rebuild | 2.437 ms | 2.464 ms |
| Long-transfer phase maxima (aircraft 5/11, first/repeat) | 81.43–130.77 ms | 23.98–25.32 ms | 24.46–45.68 ms |
| First cockpit maximum frame | 64.59 ms | 60.31 ms | 65.37 ms |
| Ground near/distant/zoom maximum frames | Not measured | 18.57 / 18.16 / 18.59 ms | 20.47 / 25.35 / 33.67 ms |

The final ground phases had p95 frame times of 17.81 / 18.35 / 19.70 ms.
All 30 spawned vehicles (six of each ground scene) reported ground support in
both runs. Near and zoom screenshots were inspected; wheels remain present.
The final zoom now requests more detailed support, so its cost is not directly
comparable to the first run's coarse-support zoom. These are stationary vehicles
on real streamed collision, not a moving convoy or full bay deployment/retrieval
test. Additional ambient frame spikes remain; this is not a universal hitch fix.

The final isolated diagnostic (`user://rock_wheel_diagnostic_shared_support.json`)
preserved all 592 rocks across an origin shift, reused all 1264 cached cells and
evaluated zero new candidates. Its synchronous helper still costs about 64 ms for
a wholly new footprint: runtime budgets distribute that work rather than remove
it. Nearby support calls cost about 34–68 microseconds per vehicle in this fixture;
coarse calls cost 12–16 microseconds. Correct support is more expensive than the
old nearby math, despite fewer rays. No blanket wheel CPU speedup is claimed.

Final regression reruns passed the four suites listed above. The budget test used
34 slices with a 2.270 ms maximum. ObjectDB leak warnings remain in focused test
teardown. Both rendered runs also logged null-material renderer errors during
teardown despite exit code 0; the older shutdown crash is not declared fixed.

Reproduce the rendered test with the Godot console executable:

```powershell
& $godot --path . --windowed --max-fps 60 --script res://Tests/ScenarioTransitionPerformance.gd --quit-after 40000 -- --test-scenario=0 --disable-campaign-autosave --label=rock_wheel_final --ground-wheel-audit
```

Next acceptance coverage should drive all ground types over uneven terrain and
through a complete moving-carrier bay cycle. The 0.60/0.65 m travel caps may need
vehicle-specific tuning; unloaded terrain still uses the existing coarse height
fallback outside physical-only carrier operations.
