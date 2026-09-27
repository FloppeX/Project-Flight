# Land carrier model integration

The live carrier in `LandCarrier/LandCarrier2.tscn` uses
`Models/LandCarrier/CarrierWithInterior.tscn`. That small inherited scene is
based directly on `Models/LandCarrier/Land carrier 4.glb`. There is no longer a
second visible carrier or interior layered over it. The hull, flight deck,
island, two island floors, and elevator all come from the new GLB.

`CarrierIslandIntegration.gd` builds walking collision from the authored island
mesh and floor surfaces, plus a separate flight-deck walking surface. The
commander's walk area uses the named lower floor, upper floor, elevator, and
`human` reference from the same GLB. `LandCarrier4VisualIntegration.gd`
reassembles the two sliding doors that Godot imports as separate top-level
meshes and attaches the existing facing-and-distance door controller. The doors
open when approached within 1 metre while facing them, remain open while the
person is within 20 cm or still facing them, and close once the person moves
away and looks elsewhere.

To rebuild the lightweight scene wrapper after editing `Land carrier 4.glb`,
run Godot's import and then the model builder from the project directory:

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --editor --path . --import --quit
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://tools/carrier_interior/build_model.gd
```

The builder checks that the required named meshes and both door mesh sets are
present before writing the scene. Keep those names in future Blender exports.
The older `export_carrier.ps1` exports the historical `CarrierUnified.glb`; it
does not update the live `Land carrier 4.glb` geometry.

Focused checks are `Tests/Carrier4IntegrationSmoketest.gd`,
`Tests/CarrierDoorFacingFleetSmoketest.gd`, `smoke.gd`, and `game_smoke.gd` in
this directory. The live game check verifies the commander's lower-floor spawn,
interior enclosure, corridor approach, elevator ride, and upper-floor exit.
Physics layer 21 is reserved for interior walking; layer 20 remains for
projectile hit volumes.