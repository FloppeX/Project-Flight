# AI scaling and scheduling audit — September 29, 2026

The reported slowdown occurs with many AI aircraft and vehicles, sometimes down
to 10 FPS. These changes address confirmed unnecessary CPU work. They have not
yet been measured in that particular gameplay situation.

## Changes

- **Aircraft separation:** both helicopter separation passes and fixed-wing
  collision avoidance now reject distant or vertically separated contacts
  before checking their altitude above terrain. That altitude check can use
  navigation-grid samples, procedural terrain queries, or raycasts. Previously
  it ran for every aircraft before the distance rejection. Nearby collision
  rules, prediction, and control cadence are unchanged.
- **Fixed-wing sensor caches:** aircraft that belong to several groups are
  deduplicated when the cache is built. Repeated contact scans no longer revisit
  those duplicates or perform a growing linear membership search for each
  accepted contact. Team, range, validity, and discovery cadence are preserved.
- **Platoon tactical updates:** contact positions and route-preview maintenance
  run at 10 Hz by default. Each platoon gets a different recurring phase. Initial
  work and new orders run on the next physics tick; membership changes also
  request an update. Elapsed time is accumulated, and a slow frame causes one
  update rather than a burst of catch-up calls. Origin shifts rebase cached
  positions immediately. Vehicle movement and weapon tracking keep their
  existing rates. A redundant second terrain projection was also removed.
- **Vehicle spacing:** an empty neighbour list is now cached for the configured
  refresh interval (0.35 seconds by default), just like a non-empty list.
  Previously emptiness forced another search on every drive-command update.

## Existing scheduling retained

Fixed-wing pilots already stagger contact scans, awareness, housekeeping and
collision checks. Helicopters already budget navigation replanning, health,
rotor wash and other supporting work. Vehicle drivers and turret controllers
already have multi-rate updates and separate offscreen budgets. NavPathScheduler
already limits path-job starts and concurrency. These mechanisms remain intact;
this change does not reduce flight stabilization or emergency-control rates.

## Validation and limits

`AIScalingDiagnostic` uses 96 lightweight aircraft bodies, real helicopter
separation methods and procedural terrain. Aircraft are 350 m apart; both
separation methods are invoked for every aircraft over 20 synthetic ticks.

| Measurement | Before | After |
| --- | ---: | ---: |
| Separation CPU time per synthetic tick | 154.9 ms | 20.5–21.3 ms |
| Terrain lookups across 20 ticks | 368,640 | 3,840 |

This is roughly seven times faster for this specific workload. It is **not** a
full-game FPS benchmark: there is no rendering, full aircraft physics or combat,
and no baked navigation grid. Dense nearby traffic will still need the terrain
checks. Whole-population group iteration remains, so this is not a complete
solution to every population-scaling cost.

`AIWorkCadenceSmoketest` verified 24 platoons: after their initial update, four
update per physics tick rather than all 24. It also checks immediate orders,
hold, elapsed time, slow-frame behavior, origin shifts, empty-cache reuse,
new-neighbour discovery, sensor deduplication, team changes, freed contacts and
nearby versus distant collision threats.

Passed regression scenes: `FormationGuidanceSmoketest`,
`HelicopterAirBehaviorSmoketest`, `PatrolWaypointProgressionSmoketest`, and
`GroundAttackPlanSmoketest` (108 checks).

Run either new diagnostic as a Godot scene, for example:

```powershell
& 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://Tests/AIWorkCadenceSmoketest.tscn
& 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://Tests/AIScalingDiagnostic.tscn
```

The next useful validation is the existing instrumented play-session launcher
in the actual crowded situation. See `AIRCRAFT_PERFORMANCE_DIAGNOSTIC.md`.
