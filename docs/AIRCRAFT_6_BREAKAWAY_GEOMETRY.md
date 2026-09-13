# Aircraft 6 breakaway geometry

Implemented 2026-09-11. `Aircraft/Aircraft_6.tscn` uses the new
`Models/Aircraft_6/aircraft_6_breakaway.glb`; the original `aircraft_6.glb` is
retained untouched as the source for regeneration.

## Structure and damage

- `Airframe` retains the fuselage, wing roots, engine mount, and tail bases.
- `OuterWingLeft` / `OuterWingRight` separate around 3.6–3.8 m from the
  centerline, outboard of the existing weapon pylons and wing insignia.
- `HorizontalTipLeft` / `HorizontalTipRight` separate around 0.9–1.1 m from
  the centerline. They retain the existing shared horizontal-stabilizer damage
  pool, but fall as **two independent physics bodies** when that zone fails.
- `VerticalTip` separates above the tail base. Its insignia follows the debris.
- Every fracture has matching zigzag geometry and closed grey-metal end caps
  on both sides. Original skin materials, UVs and faceted normals are retained.
- Existing damage thresholds and flight-control consequences are unchanged.
  Zone colliders disable on destruction using the same existing behavior as
  other fixed-wing aircraft; this does not introduce more granular root colliders.

`AircraftPartDamageModel.independent_debris_zones` is opt-in. Other aircraft
retain the default compound debris behavior for multi-mesh authored sections.
There is no runtime mesh cutting: all geometry is baked in the GLB. The split
adds five mesh nodes and fracture surfaces, rather than a per-frame slicing job.

## Rebuild

From the project root, using Blender 4.5:

```powershell
& 'C:/Program Files/Blender Foundation/blender 4.5.3/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/build_aircraft6_breakaway.py -- --build
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --editor --path . --import --quit
```

Omit `--build` to inspect the source without writing assets. The builder checks
bidirectional exterior surface coverage, total skin area, manifold detached
pieces, and matching fracture-cap surfaces before exporting. This run measured
2.424 mm maximum sampled skin deviation and 0.0290 square metres of exterior
area difference after Boolean retriangulation. The acceptance bounds are 5 mm
and 0.1% of original exterior area; the result is not mathematically identical
triangulation. Split normals are transferred from the untouched source so the
original low-poly appearance does not become smooth after welding.

## Verification

```powershell
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/Aircraft6BreakawaySmoketest.gd
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/FixedWingPartDamageColliderSmoketest.gd
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --path . --script res://Tests/Aircraft6BreakawayRenderedProbe.gd
```

- Geometry validation: **PASS**. All five detached meshes are closed/manifold;
  the matching cap area on the retained structure is 1.3437 square metres.
- Aircraft 6 damage smoke: **PASS**. Four independently tested zones, five
  physical debris pieces, sublethal retention, real shape-index damage routing,
  retained roots, unaffected-zone visibility, collider disabling, insignia
  transfer, no repeated-damage duplication, and falling under gravity.
- Shared fixed-wing damage/collider regression: **PASS** (Aircraft 1–8 and 14).
- Rendered probe: **PASS**, images inspected for original versus intact shape,
  restored faceted shading, wing/tail fracture interiors, and actual runtime
  damage with separated debris. Captures: `captures/aircraft6_breakaway/`.

These are focused geometry/damage tests. The owner is frozen for repeatability;
this was not a full combat-flight playtest. Tests still report the existing
ObjectDB shutdown-leak warning, and the fleet regression reports WingFold node
warnings; neither was introduced or resolved by this mesh change.
