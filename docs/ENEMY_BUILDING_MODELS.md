# Enemy emplacement and destroyed buildings

The production `Buildings/gun_emplacement.tscn` now uses `Models/building - enemy gun emplacement.glb`. The source GLB is unchanged. `Buildings/EmplacementTurret.gd` adapts its `turret` yaw mesh and `barrel holder` pitch location to the existing turret controller and 10/15/20 mm gun catalog. A normalized aiming pivot drives the holder while preserving its authored parent, rotation and scale. Caliber-specific barrels and their muzzle positions use the shared mounting code. Recoil moves the barrel and muzzle only, leaving the holder and base fixed.

The existing targeting ranges, health, firing cadence, enemy paint selection and distance activation remain in use. Collision follows the authored base, turret and holder. The dummy scene inherits the new model and retains its visual barrel without a live weapon.

`Buildings/gun_emplacement_destroyed.tscn` and `Buildings/building_enemy_outpost_destroyed.tscn` directly instance the new destroyed GLBs. `BuildingWreck.gd` creates collision from their actual damaged meshes. The intact collider is removed or disabled, so missing turret housings and upper floors do not remain as invisible walls. Wrecks do not target or fire. Outposts retain their existing offline map state and gameplay consequences.

Managed emplacement wrecks now survive checkpoints, including their position, rotation, faction and paint. Outpost destruction already persisted; loading a destroyed outpost now installs the authored ruin instead of the previous darkened intact model.

Validation on 2026-09-24:

- `Tests/EnemyBuildingModelsSmoketest.tscn`: 90 aiming combinations across three calibers and level/tilted hosts; maximum observed aim error about 0.028 degrees. Actual AI acquisition/damage, muzzle placement (including the existing 2.5 m projectile clearance), recoil isolation, activation, dummy behavior, ruined collision and JSON checkpoint restoration passed.
- Existing turret orientation (360 cases), barrel recoil (13 cases), outpost gameplay/persistence and bomb ground-scorch tests passed.
- `-- --render` captures `captures/enemy_building_models.png` and `captures/enemy_emplacement_rig.png`; both inspected in Forward+.

Some test shutdowns still report ObjectDB/resource cleanup warnings. These focused checks do not establish a clean renderer teardown or full campaign combat balance.
