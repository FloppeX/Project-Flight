# KMV Enforcer

`enforcer_hull.glb` is exported from `D:\3D printing files\vehicle 3.blend`.
`source.json` records the source SHA-256, Blender version, authored objects and
materials. All eleven meshes are exported with their modifiers and transforms;
the external Blender file is not modified.

Rebuild from the project directory:

```powershell
& 'C:\Program Files\Blender 5.1\blender.exe' --background --factory-startup 'D:\3D printing files\vehicle 3.blend' --python-exit-code 1 --python tools/export_enforcer.py
```

Reimport the GLB in Godot. The playable assembly is
`res://GroundVehicle/ground_vehicle_3.tscn`, based on vehicle 2 (KMV Sabretooth).
It retains the shared driver, six-wheel suspension, steering, rescue doors and
modular turret, fitted with the 20 mm autocannon profile and matching barrel.
Initial tuning is 75 health and 18 m/s, against Sabretooth's 50 health and 20 m/s.
The hull collision box follows the new body's bounds.

The scene is listed in the Technical Index and development spawn menu. Run
`Tests/Vehicle2Smoketest.gd -- --vehicle-3` headlessly for driving, wheel contact,
doors, livery, identity and weapon checks, or with rendering for front/rear
captures under `captures/vehicle_3/`. Campaign balance remains initial tuning.

`Tests/EnforcerPreviewSmoketest.gd` checks the Enforcer's 20 mm and Sabretooth's
10 mm barrel visuals in the Technical Index. With rendering enabled, it also
saves `captures/vehicle_3/technical_index.png`.
