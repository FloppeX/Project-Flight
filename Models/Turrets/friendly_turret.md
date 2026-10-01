# Friendly angular turret

Source: `D:\3D printing files\turret angular concept.blend`, including the user's
September 29, 2026 edits. Exported from the live Blender 5.1.2 scene after saving.

Export `friendly_turret.glb` as glTF Binary with Y up, no animations, and all three
objects (including the hidden `barrel position` locator). Preserve transforms and
materials. `turret body` is the yaw housing; `barrel base` supplies the pitch hinge;
`barrel position` supplies the gun insertion point. The runtime rig hides the
locator and adds the selected caliber's barrel and muzzle.

Friendly vehicles and both carrier turret assemblies use
`Weapons/Turrets/friendly_turret.tscn`. The original `turret.glb` and `turret.tscn`
remain available to other units. CarrierTurretMount seats the authored axle on the
roof without stretching or flattening the armor. Verify mounting surfaces after
source changes with ModularCarrierTurretsSmoketest and ModularTurretsRenderedProbe.
