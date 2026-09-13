Officer with coffee mug
======================

Instance `res://Models/Characters/OfficerFemaleCoffee.tscn` for the rigged officer
in the approved holding pose. Its AnimationPlayer plays `Coffee_Hold` on startup.
Three clips are available on that player's default animation library:

- `Coffee_Hold`: the approved grip and standing pose, looping.
- `Coffee_Sip`: four seconds; raise, tip, untilt, lower, and return to hold.
- `Coffee_Walk`: the regular female officer's existing 1.033-second walk loop,
  with her right shoulder, arm, hand and fingers held fixed relative to her chest.
  Her legs, torso, head and left arm retain the regular walk's motion. This is
  an in-place clip, using the same 2.4 m/s movement reference as the regular walk.

The GLB contains the original 344-bone rig, body, sunglasses, and three mug
surfaces. Godot attaches the mug to `rig/Skeleton3D/hand_r` (BoneAttachment3D).
The default insignia remains embedded for Blender/export previews. In game, the
officer replaces the mug's front material with the player's current insignia
from `Livery`, and refreshes it when the player changes that selection. Transparent
image regions blend into the white ceramic; the imported mesh/material is not
modified. New clips can animate the same
skeleton. The sip is an editable Blender IK action; the mug follows `hand.r`.
The walk is generated in Godot from the existing regular walk, with a conversion
between the two exported rest skeletons. It is stored in
`OfficerFemaleCoffeeAnimations.tres`, alongside copies of the imported hold and
sip. The walk is not a separate Blender-authored action.

The scene's controller exposes `play_sip()` and `set_walking(walking, speed_mps)`.
Sipping returns to hold automatically. Starting to walk interrupts a sip;
requests to sip while walking are ignored. Actors still own position/movement.
In the game, B selects the coffee officer and sips while standing, in commander
or free-camera view. Movement uses the carrying walk; O cycles officer variants.

For an interactive preview, run `res://tools/OfficerCoffeeAnimationPreview.tscn`
with F6. B plays a sip; W toggles walking.

Authoring source: `D:\3D printing files\Officer female - coffee mug.blend`.
To refresh the export from PowerShell at the project root:

```powershell
./tools/export_officer_coffee.ps1
```

This exports the Blender actions, reimports the GLB, rebuilds the carrying walk
from the current grip and regular walk, and runs the animation checks. The
exporter converts the insignia shader for glTF without saving source changes.
Keep pose changes keyed in the Blender action; mesh edits need no new pose keys.
The original source before adding animations is backed up as
`D:\3D printing files\Officer mug review\before_coffee_animations.blend`.

Grip recovery: the main file used for the first animation pass contained the
older straight-on hand and handle. The 45-degree grip and edited mug were
recovered from the September 13, 01:06 Blender autosave, retained permanently at
`D:\3D printing files\Officer mug review\recovered_user_grip_autosave.blend`.
Both animations were rebuilt from that recovered source. GLB rig metadata records
the exported hand angle and mug mesh fingerprint; validation compares the runtime
holding angle with the source angle.

The sip keys a `CoffeeSleeveRoll` constraint on the existing forearm twist bone
to spread sleeve rotation for Godot's linear skinning. It has zero influence in
the hold pose and does not change the hand or mug trajectory. The runtime
library also fills constant bone tracks so walk-to-sip transitions restore the
entire pose instead of retaining previous limb transforms.
