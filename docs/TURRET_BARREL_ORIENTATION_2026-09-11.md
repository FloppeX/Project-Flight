# Consistent turret barrel orientation — 2026-09-11

## Cause and changes

The legacy vehicle LMG declared local +X forward and -Z as its pitch axis,
although steering assumes +Z forward. Its imported mesh already includes the
rotation needed to face +Z; rotating the imported model again is incorrect.
Fresh pre-fix pickup and bus runs reproduced roughly 90 degrees of aim error
and zero LMG rounds with valid targets, ammunition, range and line of sight.

- LMG gameplay mounts now use +Z forward, +Y up and +X pitch, matching the
  heavy gun, helicopter side guns, modular carrier/APC guns and projectile
  direction convention. The base Turret default is also +Z, not +Y.
- Imported visual transforms remain intact. All three legacy muzzle markers
  now face +Z; the helicopter's marker previously faced -Z.
- LMG, heavy-gun and helicopter muzzle positions were measured from the
  imported mesh's forward tip vertices in barrel-mount space. Corrections
  are authored in the scenes, with no additional runtime mesh scanning.
- Aim checking and projectile spawn direction now use the same barrel
  transform. Removed the pivot-to-muzzle direction approximation: offset
  markers no longer tilt the reported aim. Removed target-directed firing
  transforms: requesting a target cannot redirect shots before the gun turns.
- A weapon-model `BulletSpawnPoint` cannot override its owning turret's
  muzzle transform. Non-turret hardpoint weapons retain their own markers.
- The heavy-gun scene instantiated two complete copies of its imported gun
  and base. Hide the stationary copy of the gun and the moving copy of the
  base, as the LMG scene already did. Only the intended gun pitches now.

No changes to target selection, aim skill/noise, rate limits, firing arcs,
burst timing, gun profiles, damage, projectile collision or vehicle physics.
The existing projectile spawn separation offset is unchanged. Actual firing
now reflects residual tracking error rather than snapping to the requested
lead point; fast moving-target balance merits later gameplay observation.

## Verification

`Tests/TurretBarrelOrientationSmoketest.gd` checks actual buggy, pickup, bus
LMG/heavy, APC and both Aircraft 9 side-gun controllers, plus all five modular
carrier calibers (10/15/20/25/40 mm). It covers cardinal/rear/oblique targets,
up/down aiming, tilted/rotated/scaled mounts, arc boundaries, turning-rate
limits, unslewed shots, multiple muzzle sequencing, missing-muzzle fallback,
weapon-marker precedence and actual spawned projectile velocity.

The rendered variant additionally checks imported barrel bounds, measured
tip positions and renders yellow lines along the firing direction for visual
inspection. Artifact: `user://barrel_orientation.png`.

Final rendered orientation run: 360 in-arc aiming cases, worst settled error
0.028 degrees, no assertions failed, exit 0. It also passed pitch-stop checks,
all 12 rig/controller projectile-direction checks, non-turret marker retention,
and the rendered mesh/tip checks. The final image was visually inspected.

Five existing regression suites also passed and exited 0:
`ModularCarrierTurretsSmoketest`, `DefenseOpsSensorSmoketest`,
`DefenseOpsMonitorSmoketest`, `BulletPointCollisionSmoketest` (61 checks), and
`BulletHitSparkSmoketest` (21 checks). No script/parse errors were found in the
final test logs. ObjectDB/resource exit warnings remain in focused tests.

### Sustained autonomous battles

Each final run uses 32 vehicles, opposing rows approximately 200 m apart,
very high test-only health and unlimited ammunition. Normal AI targeting,
lead/noise and firing gates remain enabled. Each of two sensor comparison
phases lasts eight seconds, after warm-up; physical shot totals below include
the entire fixture run. Phase counters include cosmetic rounds as well.

| Vehicle | LMGs that fired | Physical LMG rounds | Two phase round counts | Aggregate fixture damage |
| --- | ---: | ---: | ---: | ---: |
| Buggy | 18/32 | 1,810 | 1,112 / 1,254 | 515 |
| Pickup | 32/32 | 3,992 | 2,624 / 2,613 | 1,351 |
| Battle bus | 32/32 | 4,169 | 2,870 / 2,909 | 4,513 |

Bus phase counters and damage include its heavy guns. Damage is aggregate
fixture damage in a live scenario, not per-gun attribution or a hit-rate
measurement. The final buggy snapshot reports blocked line of sight for all
14 guns that did not fire; sampled errors are 0–11.82 degrees, below the normal
18-degree fire gate, rather than the old approximately 90-degree error. This
does not establish the identity of every occluder or prove every buggy will
find a firing lane. All 64 pickup/bus LMGs fired. These are ground engagements
with driving commands disabled, not comprehensive airborne or moving-target
accuracy trials. The earlier `lmg_buggy_fixed` capture predates final muzzle
placement and is not substituted for this final result.

Artifacts: `user://transition_lmg_buggy_final.json`,
`user://transition_lmg_pickup_final.json`, `user://transition_lmg_bus_final.json`.
All 38 recorded source hashes in each final capture match the final code.
Campaign save/backup sizes and timestamps were unchanged.

The full-scenario harness still emits pre-existing material/RID teardown
errors and exits 1 after writing `COMPLETE` with no assertion failures. Those
runs are not described as clean process exits. Campaign autosaving is disabled.

## Reproduction

```powershell
& $godot --headless --path . --script res://Tests/TurretBarrelOrientationSmoketest.gd -- --disable-campaign-autosave
& $godot --path . --windowed --script res://Tests/TurretBarrelOrientationSmoketest.gd -- --disable-campaign-autosave --render
& $godot --headless --path . --script res://Tests/ScenarioTransitionPerformance.gd --quit-after 20000 -- --test-scenario=0 --disable-campaign-autosave --label=lmg_pickup_final --busy-battle --battle-only --battle-seconds=8 --battle-model=vehicle_enemy_pickup
```

Use a new label for subsequent captures; replace the model with
`vehicle_enemy_buggy` or `vehicle_enemy_battle_bus` for the other fixtures.
