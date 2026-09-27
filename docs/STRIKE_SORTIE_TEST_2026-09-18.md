# Full strike sortie check — 2026-09-18

**FAIL: launch succeeded; the designated target received no confirmed damage; the aircraft was destroyed by terrain during recovery approach.**

## Observed timeline

Times are simulation seconds from test startup.

| Time | Observation |
| --- | --- |
| 40.65 | Aircraft_5 launched from the normal hangar/elevator/catapult sequence. Its runtime name was Aircraft_1_1; the scene path confirms Aircraft_5. |
| 41.38 | Archer received a CAS order around a stationary test target 3.5 km ahead of the carrier. |
| 44.40 | Climb state observed. |
| 78.62 | Attack positioning began. Five dive entries were recorded by the one-second sampler, interspersed with break-offs and repositioning. Shorter transitions may have been missed. |
| 462.05 | Seven-minute strike window ended: zero damage to the designated target. RTB ordered and accepted. |
| 505.35 | Recovery approach began; landing clearance was granted. |
| Before 716 | Three recovery reacquisition starts were logged for missing route progress/progress timeouts. |
| 716.02 | RightWingDamageCollider contacted a terrain chunk at 74.57 m/s and triggered destruction through `_evaluate_terrain_impact`. |
| 716.63 | Test reported FAIL and exited with code 1. No touchdown, wire catch, or storage was recorded. |

The aircraft retained 100% health until the destructive collision and approximately 49.94 fuel units at the last sample. Fuel exhaustion did not cause this loss. A separate combat-log hit is not evidence that the designated target was hit.

## Method and limits

`Tests/FullStrikeSortieProbe.gd` extends the existing full-scenario recovery observer. It uses the real main scene, an Aircraft_5 requested with the normal rocket-strike loadout, a player-style carrier route, CAS and RTB APIs, normal flight physics, finite fuel/ammunition, normal recovery supervision and unchanged wire gates. No aircraft repositioning, forced catches or save writes are used. Enemy operations/base spawning are disabled in the harness; existing scene contacts are not explicitly cleared. The test target is a non-firing 12 x 8 x 12 metre static body placed at terrain height, with 500 health. CAS selects contacts within the ordered area rather than enforcing exclusive targeting of that body.

This run used the current 70 m/s progressive-control reference, placement seed 20260911 and normal open_canyons terrain/weather. It was a headless 60 Hz physical simulation, not a rendered visual/handling acceptance test. The runner allows 600 seconds for launch, 420 seconds for the strike and 900 seconds for recovery. It requires designated-target damage, a wire catch and hangar storage for PASS.

This is a single run, without a matched 100 m/s baseline. It does not establish that the revised controls caused either failure. Earlier recovery failures are documented in WIND_RECOVERY_CHECK_2026-09-17.md. Next investigation should separate attack target acquisition/release/accuracy from recovery route tracking and terrain clearance. Do not weaken final landing gates to conceal upstream approach failures.

The sampled terrain height at destruction was 620 m while the aircraft origin was at 705.30 m. The collision metadata identifies a right-wing contact against a terrain chunk; the single height sample does not explain the geometry discrepancy. Inspect the actual collision geometry and surrounding terrain before attributing it to a bad height query.

The run emitted imported-scene/physics-interpolation warnings, a JSON NaN-to-null warning in recovery telemetry and shutdown resource warnings. No SCRIPT ERROR was found. Non-finite telemetry fields should not be treated as valid measurements.

## Artifacts and reproduction

- `logs/strike_sortie_control70.log`: stdout and collision/recovery diagnostics.
- `logs/strike_sortie_control70.jsonl`: sampled states and events.
- `logs/strike_sortie_control70_status.json`: terminal aircraft status.

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/FullStrikeSortieProbe.gd -- --label=strike_sortie_control70
```

The runner also writes the event and status files under Godot's `user://` directory. Reuse a different label to preserve earlier runs.
