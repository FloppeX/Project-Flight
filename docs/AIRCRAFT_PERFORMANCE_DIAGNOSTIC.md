# Aircraft performance investigation

The September 29 check did not reproduce the reported gameplay FPS drop. The
editor game was stopped, and the latest hitch log belonged to a diagnostic scene.
Do not treat the isolated timings below as full-world FPS measurements.

## Findings

- Aircraft source imports already enable generated mesh LODs.
- A rendered Vulkan comparison of 16 real helicopters (Aircraft 10, 13, 15),
  roughly 1.4 km away, used about 69,434 primitives and 145 draw calls. Changing
  mesh LOD bias from 1.0 to 0.2 did not materially change either count. Baseline
  frame time was about 0.9 ms; the lower bias had no consistent speed benefit.
- All 16 helicopters survived the corrected simulation phase. This phase hides
  aircraft rendering and uses flat terrain, running engines and hover orders.
  It does not represent combat, navigation over real terrain, or the full world.
- Saved settings used the highest view-distance level, TAA and 100% render scale.
  Their contribution needs an actual gameplay capture; they were not changed.
- A separate, confirmed CPU problem occurred when no terrain provider existed:
  repeated aircraft height requests traversed the whole scene every time.
  `TerrainReference` now caches an unsuccessful search until the tree changes,
  while still checking for newly tagged providers. Detached/freed providers are
  rejected. A 4,000-node test took approximately 2.7 ms for 1,000 cached requests
  versus 2,294 ms for 1,000 forced traversals. This is a missing-terrain lookup
  comparison, **not** a claimed gameplay FPS improvement.

## Reproduce

Run the rendered diagnostic by selecting
`res://Tests/AircraftPerformanceDiagnostic.tscn`, or from PowerShell:

```powershell
& 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe' --path . --windowed --resolution 1280x720 res://Tests/AircraftPerformanceDiagnostic.tscn
```

The diagnostic writes `logs/aircraft_performance_diagnostic.json`. It uses ABBA
ordering for the mesh-bias comparison, freezes aircraft for rendering phases and
hides them for simulation. It does not load or write a campaign save. It does
load project autoloads and graphics settings; the report records the resulting
viewport size. Run only one game process when comparing timings.

The terrain lookup regression check is:

```powershell
& 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://Tests/TerrainReferenceSmoketest.gd
```

For the actual slowdown, start a normal instrumented play session:

```powershell
.\tools\run_logged_play_session.ps1
```

This launcher now defaults to the installed Godot 4.7.2, accepts `-GodotPath`,
and records engine metrics and CPU scope reports. Reproduce the slow view with
the same camera, then compare view-distance settings. Captures are saved under
`%APPDATA%\Godot\app_userdata\Land Carrier\perf_play_sessions`; the active
capture path is also recorded in `captures/perf_play_sessions/active_session.txt`.
