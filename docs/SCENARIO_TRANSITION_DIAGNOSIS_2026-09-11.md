# Real-scenario transition profiling — 2026-09-11

Follow-up: the shared map cache and stable navigation-frame changes are now
implemented. See [new measurements and remaining issues](TRANSITION_SHARED_MAP_STABLE_NAV_2026-09-11.md).
The diagnosis below preserves the pre-optimization evidence.

## Scope and confirmed finding

The large first-cockpit stall is not just instrument-panel allocation. The
cockpit radar synchronously generates its own terrain-map image from `_draw()`.
In `transition_scenario_scoped.json`, this took **1866.006 ms** inside a
**1934.048 ms** frame. `WorldMapTextureBuilder.build_images()` accounted for
1865.518 ms of that scope; these are nested times, not additive costs.

The same map builder had already run during scenario startup (1833.077 ms in
the scoped run's console/hitch trace). `WorldMapOverlay` and `RadarCanvas` each
request their own build. Even the radar's relief-only request generates both
relief and mobility images. Existing per-panel caching prevents subsequent
draws from rebuilding, but does not share the startup map with the cockpit.

This pass adds diagnostics and test coverage, **not a production optimization**.
Aircraft aerodynamics, camera motion, floating-origin policy and terrain quality
are unchanged.

## What was exercised

- Real `Main_Scene.tscn`, generated Open Canyons terrain, the actual carrier's
  Commander/control-room camera, instruments and monitors.
- Real Aircraft 1, 5 and 11: first and repeat visits, roughly 8.6–9.3 km
  aircraft transfers, returns to the bridge, rapid retargeting, player takeover.
- Only the three test targets have flight/physics suspended; normal background
  carrier operations, enemy operations, terrain and floating origin remain on.
  Background orders can still reference the stationary targets.
- Scenario/menu settings are not rewritten. Campaign autosaving is disabled in
  the harness. Existing campaign save timestamps were checked unchanged.
- The terrain profile/bake center is fixed, but normal carrier safe-placement
  and background activity can vary between runs. This is not a deterministic
  cross-run A/B benchmark or a test of flying/landing behavior.
- Ground-vehicle possession was not exercised. The current FlightDirector
  handoff API takes aircraft `RigidBody3D` targets; the friendly ground vehicle
  is a `CharacterBody3D`, so a fabricated aircraft-style handoff would not test
  the real player flow.

Forward+ / Vulkan, RX 7800 XT, 60 FPS cap, 1280×720 window with configured
1920×1080 internal viewport. Screenshots were taken outside measured windows,
followed by three quarantine frames. Native viewport PNGs confirmed the real
cockpit, terrain and carrier interior were rendered; this is not a headless
rendering claim.

## Recorded instrumentation

`Tests/Fixtures/TransitionRenderTrace.gd` records each viewport's CPU/GPU
render timings, CPU frame setup, draw-signal wall time and pipeline counters.
The normal frame trace includes transition phase, terrain backlog and correlated
CPU scopes. Scope timing now includes radar map construction, rock streaming,
plant streaming, main-thread path requests and origin-shift work.

Render queries describe recently completed render work and can lag the script
frame. Disabled or WHEN_VISIBLE viewports can retain stale times; **do not sum
every viewport's reported time**. Inspect neighboring frames and keep CPU/GPU
measurements separate. Performance process/physics monitors can also update
less frequently than the raw wall-frame samples. These interpretation rules
follow the [Godot 4.6 RenderingServer reference](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-cpu).

The main-thread FrameProfiler collector is not called from worker path jobs.
Production instrumentation adds no new scene traversal, graph copy, texture
allocation or always-on render measurement. Per-viewport measurements are
enabled only by the test harness. The first full capture's maximum render-trace
sample overhead was 0.137 ms.

## Full scenario, scoped run

Artifact: `user://transition_scenario_scoped.json`.

| Phase | p95 frame | Worst frame |
|---|---:|---:|
| Bridge idle | 17.22 ms | 18.24 ms |
| First Aircraft 1 | 17.52 ms | 1934.05 ms |
| First Aircraft 5 | 20.24 ms | 108.91 ms |
| First Aircraft 11 | 19.01 ms | 99.36 ms |
| Repeat Aircraft 1 | 17.61 ms | 31.59 ms |
| Repeat Aircraft 5 | 17.72 ms | 98.34 ms |
| Repeat Aircraft 11 | 22.12 ms | 97.33 ms |
| Bridge returns | 17.45–17.71 ms | 21.51–21.82 ms |
| Rapid retarget | 17.51 ms | 26.78 ms |
| Player takeover | 17.53 ms | 18.16 ms |

At first Aircraft 1 arrival, the actual final handoff CPU scope was **7.461 ms**,
including **0.586 ms** panel checkout. The radar build dominates the stall.
Main-viewport GPU time remained below 1.92 ms across the scoped run. This does
not prove that every renderer synchronization cost is absent, but it rules out
ordinary sustained main-view GPU saturation as the explanation for 1.9 seconds.

The earlier full capture (`scenario_render_v2`) reproduced a 1946.37 ms first
arrival and also had an unexplained 1165.12 ms pause during a later transfer.
That latter pause did not repeat in the scoped run; it must not be attributed
to pathfinding or rendering merely from coincidence.

## Origin-shift confirmation

The third full capture, `user://transition_scenario_origin.json`, adds direct
timing around floating-origin notification, navigation's mutex acquisition and
navigation's node/index rewrite. It confirms a second, independent main-thread
stall:

| Measured event | Frame | Origin shift | Navigation lock wait | Node/index rewrite |
|---|---:|---:|---:|---:|
| Repeat transfer to Aircraft 5 | 586.547 ms | 567.092 ms | 489.638 ms | 70.778 ms |
| First transfer to Aircraft 11 | 400.050 ms | 381.336 ms | 305.245 ms | 69.494 ms |

The graph has **186,953 nodes**. On each world-origin translation,
`NavGraph.apply_origin_shift()` waits for the same mutex held by worker
pathfinding, translates every node, and rebuilds the spatial index. Even without
the long mutex wait, measured rewrites were around 70 ms (maximum 71.58 ms in
the captured hitch scopes). Ordinary shifts took about 76 ms and produced
roughly 100 ms frame gaps; active background path work made some much worse.

This establishes lock contention as a real contributor in this run, but does
not retroactively prove the cause of the earlier uninstrumented 1165 ms event.
The radar stall reproduced again: **1856.914 ms** inside a **1930.042 ms** frame.
Main-view GPU time stayed below 3.70 ms for this entire run. Terrain chunk
processing in the correlated hitch scopes was at most 3.27 ms. Rock rebuilding
was usually smaller but reached 64.08 ms in a captured event: it remains worth
budgeting after the map duplication and navigation translation are addressed.

## Recommended implementation order

1. **Share one map result per navigation-data generation.** Produce relief and
   mobility images once, off the render/UI critical path; let tactical maps and
   cockpit radars share the result. Snapshot plain grid data on the main thread,
   build from that immutable snapshot on a worker (or bounded slices), then
   create/install textures on the main thread. Invalidate for actual grid/profile
   replacement, not floating-origin translations. Keep radar bounds in the live
   coordinate frame. Preserve resolution, colors and mobility masks.
   - Expected benefit: removes roughly **1.87 s** of duplicated CPU work from
     first cockpit use in this configuration, not a promise of hitch-free frames.
   - Two 720×720 RGBA layers use at most **4.15 MB** of pixel data per copy;
     share CPU/GPU resources rather than adding one cache per aircraft. Release
     obsolete generations and reject stale worker results after scenario changes.
2. **Avoid rebuilding navigation geometry just to translate the world.** Inspect
   origin shifts separately from terrain chunk generation. A stable map-local
   navigation coordinate system could turn graph translation into an offset
   update; it must retain equivalent paths, clearances and nearest-node results.
   Queued requests and results finishing after a shift require explicit
   coordinate-frame conversion. Do not disable floating origin or simply raise
   its threshold to hide the stall.
   - Expected benefit: remove the roughly **70 ms graph rewrite** and the
     **305–490 ms main-thread waits** demonstrated here. Other world-shift
     notifications still cost time, so zero-cost shifts are not promised.
3. **Re-measure remaining first-draw and rock-streaming costs.** Rock rebuilding
   adds several milliseconds during transfers, but the scoped run did not show
   it accounting for the roughly 100 ms spikes on its own. Keep the existing
   bounded terrain finalization and two-panel pool while addressing the proven
   sources first.

Acceptance tests for the map fix: equivalent rendered images, two radars plus
tactical map sharing one build, no rebuild after origin translation, correct
replacement after navigation rebake, no late result from a previous scenario,
and no synchronous map generation during cockpit draw. Then repeat this exact
rendered transition sequence before changing navigation's coordinate system.

## Controlled rendering comparison

`user://transition_isolated_render.json` repeats the earlier simple-ground,
frozen-aircraft fixture with the new per-viewport timing. It completed with no
assertion failures and exit code 0 (an ObjectDB leak warning remains).

The first arrival is **48.372 ms**, with a **5.920 ms** final-handoff CPU scope.
A nearby frame reports **22.295 ms** between render pre/post-draw signals,
while reported main-view GPU time stays below 0.78 ms throughout the sequence.
Pipeline counters at arrival include four additional surface compilations and
one canvas compilation;
the draw-compilation counter stays zero. These results support further
first-use render/driver synchronization investigation, **not a precise
attribution of the entire 48 ms stall**. The expensive radar build and origin
shifts cannot occur in this fixture because its navigation/terrain and floating
origin are disabled. All other measured transition windows peaked at 17.18 ms
or less at the 60 FPS cap.

This residual is lower priority than the independently measured 1.86-second
map rebuild and 0.3–0.6-second origin-shift stalls in real scenarios.

## Completion versus shutdown

Focused regressions passed with exit code 0:

- `WorldMapMobilityTextureSmoketest.gd`: relief/mobility layer semantics.
- `NavGraphBuilderEquivalenceSmoketest.gd`: 24 graph/path equivalence cases.
- `FloatingOriginRigidBodySmoketest.gd`: translated physics bodies remain in
  their new coordinates after the next physics tick. Its test-only preload was
  changed to runtime loading because eager compilation preceded GameSession
  autoload registration; no production behavior was changed for this test fix.

`git diff --check` passed for the changed tracked files. The origin-confirmation
capture's recorded source hashes were checked against the finished production
and harness files. Normal ObjectDB shutdown warnings remain in these small tests.

All three full captures saved `status=COMPLETE` with no handoff/panel/retarget/
takeover assertion failures and both pooled panels returned. **All three processes
then crashed during teardown** with null-material/RID diagnostics. Explicitly
freeing the scene before autoload shutdown did not resolve this. The captured
in-game timings remain available, but these are not clean process-exit passes.
Shutdown/resource lifetime needs separate investigation; it is not evidence of
an in-game transition crash.

The first attempted full run (`scenario_render`) is excluded: its harness used
the wrong terrain-height method signature, stopped before the sequence, and was
terminated. A watchdog and the correct world-position API are now in place.

## Reproduction

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --path . --windowed `
  --resolution 1280x720 --max-fps 60 `
  --script res://Tests/ScenarioTransitionPerformance.gd --quit-after 40000 `
  -- --test-scenario=0 --disable-campaign-autosave --label=scenario_check

./tools/summarize_transition_trace.ps1 `
  -Path "$env:APPDATA\Godot\app_userdata\Land Carrier\transition_scenario_check.json"
```

Run only one performance capture at a time. JSON and screenshots go to
`user://transition_<label>*`; JSON includes source hashes and phase boundaries.
