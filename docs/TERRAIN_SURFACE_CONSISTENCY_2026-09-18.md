# Terrain surface consistency â€” 2026-09-18

The public terrain height query now interpolates the actual mesh triangle, using the same processed vertex heights and diagonal selection as collision. Previously it sampled and quantized the underlying noise directly, omitting cliff processing and triangle interpolation. Navigation's batch sampler now uses the same surface query.

The shared grid builder preserves the existing mesh processing order and activation conditions. Query grids are cached in terrain-local coordinates, capped at 256 streamed chunks, and invalidated by layout refresh/rebuild. Worker mesh builds do not mutate the query cache. Non-streamed terrain uses its whole-mesh grid, matching its collision construction. Changing terrain configuration requires rebuild, as for collision. Height profile revision is now 3; navigation cache fingerprints also include the script contents.

## Verification

- Reconstructed the original crash region from the recorded seed, scene settings and terrain position. The original raw height still reproduces the recorded 620 m, verifying the source frame. Corrected height at the aircraft origin is 690.68494 m; collision is 690.68506 m.
- Across 215 recorded flight positions and 25 nearby crash-area positions, maximum query/collision error is 0.000494 m. Collision heights at all 215 original positions and the impact point are unchanged from the earlier reconstruction.
- `TerrainSurfaceParitySmoketest`: 648 raycast comparisons across both map profiles, quantization enabled/disabled, streamed/full-mesh modes, chunk boundaries and truncated edge chunks; maximum error 0.000672 m. Also checks queries before collision streaming, origin translation, outer boundaries, out-of-bounds NAN and rebuild invalidation.
- `TerrainBatchAndGraphSchedulingSmoketest`: PASS, including scalar/batch equality and graph publication/cancellation.
- `RecoveryTerrainEscapeSmoketest` and `RecoveryClimbAuthorityProbe`: PASS with the corrected terrain code. These remain controller/state checks, not proof of physical recovery.
- Crash-region warm-query measurement: 10,000 queries in 57.53 ms, with 13 cached chunks using 87,412 bytes of packed height data. This excludes dictionary overhead and is not a worst-case cold-cache benchmark.
- The operational run's cold navigation bake took 79.2 seconds and total scenario loading took 111.7 seconds on this run. The old trace used cached navigation, so its 12.5-second load is not a like-for-like performance comparison. Cold bake slices reached 1.25 seconds; loading responsiveness remains a limitation.

The physical parity tests cover the project's unrotated, unit-scale terrain and origin translations. The existing batch test verifies scalar/batch agreement under other transforms, not collision parity for tilted/scaled terrain.

## Artifacts

- `logs/sortie_terrain_corrected.json` and `.log`: corrected reconstruction, preserving the original reconstruction separately.
- `logs/terrain_surface_parity.log`, `logs/terrain_batch_surface_check.log`: geometric and navigation tests.
- `logs/recovery_terrain_surface_check.log`, `logs/recovery_climb_surface_check.log`: controller checks.
- `logs/strike_sortie_terrain_fixed.log`: physical operational sortie, fixed 60 Hz simulation.

Known material-remapping, imported-scene and shutdown resource warnings remain in the headless runs. No script errors were found in these completed focused checks.

## Operational sortie result: PASS, with slow recovery

Command: Godot 4.6.2 `--headless --path . --fixed-fps 60 --script res://Tests/FullStrikeSortieProbe.gd -- --label=strike_sortie_terrain_fixed`.

The normal hangar/elevator/catapult launch, CAS order, finite fuel/ammunition and RTB/recovery systems were used, with the same stationary non-firing target harness. No aircraft teleport, forced catch or relaxed wire gate was added. This run includes both the earlier narrow climb-authority repair and the terrain-query correction. It is not a deterministic replay or an isolated attribution experiment; navigation data, target height, timing and resulting flight trajectory differ from the original run.

| Event | Simulation time |
| --- | ---: |
| Launched | 80.93 s |
| Target damage confirmed: 100 | 217.98 s |
| Recall ordered | 217.98 s |
| Wire 2 caught, health 100 | 993.92 s |
| Stowed, health 100, fuel 33.87 | 1028.33 s |

The process exited 0 and the explicit sortie result passed. Wall time was about 355 seconds, including the cold load. There were six pre-landing entries and five missed approaches. Recovery from recall to stow took 810.35 seconds, leaving less than 90 seconds of the harness's 900-second recovery window. Three touchdown events were reported after the wire catch, two classified hard (approximately 3.1–3.2 m/s sink) but none damaging. There were no crash signals or aircraft destruction.

This establishes one observed successful launch/strike/RTB/wire/stow cycle. It does not establish reliable or efficient recovery, repeated mission reliability, combat survivability, or fleet-wide landing coverage. The next investigation is recovery approach tracking and the pre-landing handoff: initial entries were hundreds of metres laterally displaced and roughly 610 m above the final waypoint. The snapshot's vertical-error field measures height above the segment endpoint, not deviation from the interpolated descent path, so it must not be interpreted as the latter.

The complete trace and status are copied to `logs/strike_sortie_terrain_fixed.jsonl` and `logs/strike_sortie_terrain_fixed_status.json`. No SCRIPT ERROR occurred. Dummy-renderer null-material errors and shutdown warnings remain after completion.
