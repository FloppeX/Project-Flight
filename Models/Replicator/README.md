# Replicator asset

`replicator.blend` is the authored chamber and compartment used by the game.
Save edits directly in this file; Godot automatically imports it through the
configured Blender installation. No manual GLB export is needed.
`LandCarrier/ReplicatorChamber.gd` loads the imported Blender scene, including
its materials and separate meshes. The older `replicator.glb` is retained as
the original generated asset and is no longer loaded during gameplay.

The top-level groups are:

- `FabricationFrame`: pad rim/seal, overhead octagon and support columns.
- `CarrierCompartment`: floor, ceiling, walls and transfer rails. Hide this
  group while editing the machine in Blender.
- `TransferPlatform`: movable floor tray and its markings.
- `DescendingShield`: eight glass panels and their lower seals.
- `Arms/Arm_0` through `Arm_3`: independent Upper, Forearm, Joint and Tool
  nodes, with the arm index appended to each name.

The exported shield is lowered and the arms are parked. Hide
`DescendingShield` as well to work on the interior.

The upper housing, lower rail, glass, shield seals and tray border have
22.5-degree mitred ends. Both the inner and outer corners meet, forming
continuous octagons without gaps or overlapping rectangular ends.

Keep those control nodes and names when editing the Blender file. Godot wraps
the authored `Replicator` empty in an additional imported scene root. Arm links
use local +Y as their length axis and one metre of base length; Godot positions
and scales them between the current joints. The shield and tray move as groups.
Products rest on the top surface of `TransferPlatform/BuildPadFloor`; its mesh
height and the tray group's elevation are read from the imported scene. Keep
that mesh name when raising or reshaping the tray in Blender.
Welding beams, sparks, glow, audio, camera and scene lighting remain runtime
effects. Products being fabricated use their separate vehicle/weapon assets.

To regenerate the original GLB geometry (optional reference only):

```powershell
& 'C:/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/export_replicator.gd
& 'C:/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --import --quit
```

Regenerating replaces the old GLB, but does not change the Blender source or
the model used by the game. The construction routine
`_build_chamber_source()` is retained for this export tool; normal gameplay
instantiates the imported asset.
