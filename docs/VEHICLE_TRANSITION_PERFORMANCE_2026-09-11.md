# Vehicle-transition presentation pass — 2026-09-11

## Outcome

Removed a measured first-visit HUD construction stall and cached instrument
panel surface geometry. This is a **partial transition improvement**, not a
claim that all vehicle-switching hitches are fixed.

The controlled Forward+ probe used real Aircraft 1, 5 and 11, normal
FlightDirector handoffs, nearby and approximately 8.7 km transfers, and repeat
visits. Flight/AI were disabled and the bodies frozen. A bridge-camera proxy
and a simple rendered ground plane isolate presentation: this does **not**
exercise the real carrier interior, generated terrain streaming, ground
vehicles, or a busy combat scenario.

## Findings and changes

- Initial `HeadsUpDisplay` root restoration took **38.976 ms** in the validated
  baseline. More detailed instrumentation isolated about **28.155 ms** in
  material setup, versus about 4.6 ms in control construction.
- Merely spreading the control setup across frames did not remove that cost.
  That experiment was removed; the synchronous HUD API is unchanged.
- The pool now primes a real HUD and the two panel surfaces in a temporary
  **256 x 256 isolated render viewport** during startup. Hidden world-space
  surfaces were not exercising their first-draw material path before.
- Importantly, the pool retains the warm HUD material after freeing the
  temporary HUD. Without retaining the shader variant's last reference, the
  next aircraft HUD still incurred the material setup stall. In the final run,
  HUD root restoration was **5.250 ms**.
- `PanelSurfaceCache.gd` caches geometry per mesh resource for display fitting,
  UV validation and interaction-ray tests. Mesh edits invalidate it; duplicated
  meshes get independent caches. This avoids repeated `surface_get_arrays()`
  calls. It does not change the triangles used for interaction or UV mapping.
- The 2D HUD and instrument-display viewports explicitly disable 3D rendering.
  The separate target-camera viewport remains 3D-capable and shares the live
  game world.
- Added fine-grained CPU scopes for HUD preparation, panel aircraft binding,
  surface binding and geometry reads. Pool warm-up elapsed time spans frames;
  it must not be reported as a synchronous blocking duration.

The live panel reserve remains **two**. The extra render world and warm HUD
are freed after startup; one material reference is retained. CPU geometry is
kept for the lifetime of its mesh, rather than as an unbounded per-vehicle
global cache. No aircraft physics, camera-transition timing or terrain
streaming settings were changed in this pass.

## Final rendered measurement

Artifact: `user://transition_verified.json`, `status=COMPLETE`, no probe
failures. It records production/test SHA256 hashes, per-frame timings,
per-phase CPU scopes and final pool ownership. All six cockpit visits obtained
their live panel; after returning to the bridge, both panels were available.

| Phase | 95th-percentile frame | Worst frame |
|---|---:|---:|
| First visit to Aircraft 1 | 16.73 ms | 46.49 ms |
| First visit to Aircraft 5 | 16.73 ms | 16.93 ms |
| First visit to Aircraft 11 | 16.73 ms | 16.79 ms |
| Repeat visits (1/5/11) | 16.71–16.72 ms | 16.79–16.82 ms |
| Returns to bridge proxy | 16.73–16.82 ms | 17.07–17.14 ms |

The run is capped at 60 FPS: these figures do not establish an uncapped FPS
gain. Panel checkout was about 0.59 ms on the first Aircraft 1 visit and
0.11 ms on its repeat visit; Aircraft 5 was about 0.57 / 0.10 ms.

The worst first-arrival frame is **not materially improved** (baseline
47.65 ms; final 46.49 ms). Its measured final-handoff CPU work was only
5.48 ms, including 0.59 ms panel checkout. The remaining time is not explained
by these CPU scopes; first-draw rendering/synchronization is a candidate,
not yet a proven diagnosis.

Early harness runs were discarded: one allowed AI to wake, one used the wrong
delta/exit guard, and one bypassed FlightDirector's normal UI-release pass.
Screenshot readback/encoding and window resizing were subsequently excluded
from measured windows. Therefore the raw reduction from three >33 ms frames
to one is **not wholly attributable to the production changes**.

## Verification and rendered inspection

Passed:

- `PanelSurfaceCacheSmoketest.gd`: reuse, geometry edits, independent duplicates.
- `InstrumentPanelPoolSmoketest.tscn`: reuse, binding, restoration of original
  material overrides, render warm-up and global pool ownership.
- `FlightDirectorAircraftTransitionSmoketest.gd`: moving endpoints, retarget/
  freed-target cancellation, staged restoration, bridge/helicopter handoffs.
- `CameraViewportIsolationSmoketest.gd`: gameplay camera switches leave monitor
  and schematic cameras alone.
- `InstrumentPanelTargetCameraSmoketest.tscn`: target-camera stabilization,
  acquisition, zoom and display settings.

The computer-use skill was used for attempted live inspection. Windows
activation reported `GetCursorPos failed: Access is denied (0x80070005)` and
window captures were black; no further UI inputs were used. Godot's actual
Forward+ viewport PNGs were inspected instead. Aircraft 1's panel and HUD
rendered; Aircraft 11's panel is inverted in **both baseline and final** images.
That existing UV/orientation issue was left out of this performance change.

Known shutdown ObjectDB/resource warnings remain. No clean-shutdown claim is
made. One headless run also reported existing tuner-log lock warnings.

## Reproduce and next work

Follow-up: [real-scenario profiling](SCENARIO_TRANSITION_DIAGNOSIS_2026-09-11.md)
identified a separate roughly 1.9-second first-cockpit radar map build which
the simple terrain-free fixture could not exercise.

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --path . --windowed `
  --resolution 1280x720 --max-fps 60 `
  --script res://Tests/VehicleTransitionPerformance.gd --quit-after 40000 `
  -- --label=transition_check
```

Results and PNGs go to `user://transition_<label>*`. Do not run other Godot
tests simultaneously with a performance capture. The probe switches its
temporary window to 1280 x 720 after the normal resolution autoload has run;
the configured internal content viewport remains 1920 x 1080 on this machine.

Next: capture the residual first-arrival frame with render-thread/GPU timing,
then repeat in the actual carrier/generated-terrain scenario. Include real
carrier interior activation, aircraft/ground-vehicle transitions, fast
retargeting and player-control takeover. Do not enlarge the pools or broadly
keep secondary world views running without that evidence.
