# Unified carrier export

The live carrier (`LandCarrier/LandCarrier2.tscn`, used by `Main_Scene.tscn`) uses
`Models/LandCarrier/CarrierWithInterior.tscn`. This lightweight inherited scene
references `Models/LandCarrier/CarrierUnified.glb` directly: hull, deck, island,
interior and doors. The build step generates scripts and metadata overrides;
it neither merges GLBs nor copies geometry into another scene resource.
The old `CarrierInteriorModel.scn` is no longer used by the current carrier.
The separate legacy `LandCarrier.tscn` still uses its older carrier model.

Source: `D:/3D printing files/Land carrier - unified.blend`.
The previous island-interior Blender file and separate GLBs are retained as
historical sources, but are not used by this export pipeline.

Save that file in Blender, then run this from the project directory:

```powershell
.\tools\carrier_interior\export_carrier.ps1
```

Add `-Validate` to run the existing door, stair and elevator checks after rebuilding.
The script reads the saved file, so save Blender edits first. Use `-BlendFile` if
you save a renamed copy. Logs are written under `%TEMP%/ProjectFlight-CarrierExport`.

The individual rebuild stages are:

1. Run Blender in background with that file and `--python tools/carrier_interior/export_unified.py`.
2. Run Godot `--headless --editor --path . --import --quit`.
3. Run Godot `--headless --path . --script res://tools/carrier_interior/build_model.gd`.
4. Run `smoke.gd` and `game_smoke.gd` in this directory with Godot `--headless --path . --script res://tools/carrier_interior/<name>.gd`.

The Blender source now contains the four thick threshold plates, widened upper
stair turn, cleared rail ends and hatch clearances. The exporter does not alter
geometry. The GLB instance makes the result visible in the Godot editor;
runtime scripts add collision, local utility lights and doors.

All mesh, text, curve and empty objects in the source scene are exported.
Keep reference geometry outside the export scene. Put added interior geometry in
an `ISLAND...` collection so it receives interior walking collision. Keep
the original island/floor/elevator object names, and keep each sliding door's
root, two leaf meshes and custom properties. Moving or rotating a whole door
assembly preserves its local animation. If you remodel its aperture or apply
scale to its meshes, update `opening_width_m`, `opening_height_m` and the leaves'
signed `open_offset_x_m` accordingly. Substantial route changes may require
updating the test waypoints and utility-light positions; export alone cannot
guarantee clearance for an arbitrary new layout. The hull and deck are grouped
in `CARRIER | Body and deck`; island collections remain separately editable.
This is one asset file, not one welded mesh: doors, ramps and elevator surfaces
retain their names, transforms and separate objects for game animation. Runtime
tracks, weapons, aircraft and other game entities remain in the carrier scene.

Pre-sync backup: `D:/3D printing files/Carrier interior review/before_authoring_godot_fixes.blend`.

Doors use authored opening dimensions and signed leaf travel. A character within
the approach volume opens them over 0.65 seconds. They wait 1.25 seconds after the
last character leaves before closing; re-entry reverses closing. `CharacterBody3D`
actors are recognized automatically, except the ancestor carrier. Other physics
bodies can opt in with the `door_users` group. Rendering and collision clip at the
jambs to conceal retraction in thin walls. The door mesh remains separate from
the fixed frame.

Physics layer 21 is reserved for interior walking; layer 20 remains projectile
hit volumes. The commander's existing carrier-local movement now queries the
interior surfaces, steps over treads, checks body clearance and prevents walking
off unsupported edges. The observation room keeps its original automatic lift.

`smoke.gd` checks all 16 door approaches, closing, occupancy, re-entry, movement of
the carrier, door passage clearance and both directions through the stairs.
`game_smoke.gd` loads the actual carrier scene and checks corridor/lift/observation
room access. It also verifies that `CommanderBridgeSpawn` overrides imported
reference positions and places the commander on the bridge floor with body
clearance and a ceiling overhead. Move that marker in `LandCarrier2.tscn` when
deliberately changing her starting location. `render.gd` produces Forward+ door/stair images in the source review
directory. The full-scene probe currently reports renderer null-material warnings
after the carrier is freed, despite the route assertions passing. This also
reproduces with the door controllers removed; its cause is not yet resolved.
`teardown_probe.gd` retains that reproduction (`-- --baseline` uses the old model).
Short probes also report project autoload resource cleanup warnings at exit.
