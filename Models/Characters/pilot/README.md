# Canonical pilot character

`PilotCharacter.tscn` is the only live pilot character scene.

- `pilot.glb` is the retained visible mesh and Auto-Rig Pro skeleton.
- `animations/running.fbx` is a hidden Mixamo motion source retargeted onto that skeleton.
- `animations/parachuting.fbx` is a hidden Mixamo motion source retargeted onto that skeleton.

Aircraft, ejection, parachute preview, and downed-pilot gameplay all use the same visible mesh. Animation-source meshes are hidden at runtime and exist only to provide bone motion.

## Shared baked animations

`animations/pilot_animation_library.tres` contains ARP-native tracks and is
attached to `PilotCharacter.tscn` as `BakedAnimationPlayer`. Call
`play_baked_animation(&"clip_name")` on the `PilotCharacter` root so the dense
ARP control rig is reset cleanly before playback; `stop_baked_animation()`
stops it.

Looping clips:

- `idle_breathing`, `idle_neutral`, `walk`, `run`
- `sit_1` (from `Sitting.fbx`) and `sit_2` (from `Sitting Idle.fbx`)
- `piloting`, `parachute`

One-shot clips:

- `turn_left`, `turn_right`, `salute`, `wave`, `die`

`Aircraft/CockpitPilot.tscn` starts the looping `piloting` clip automatically.
It is the shared cockpit-pilot scene used by the aircraft variants. The visible
pilot branch is hidden only while that aircraft's cockpit camera is current and
is restored for chase, cinematic, and other external cameras.
In the editor, the shared scene freezes `piloting` at 1.5 seconds so every
aircraft scene displays the actual seated mesh while its transform is aligned.
Reload an already-open aircraft scene after changing the shared preview.

Open `res://tools/PilotAnimationViewer.tscn` and press F6 to inspect every baked
clip in motion. It starts on `piloting` and provides clip selection, play/pause,
timeline scrubbing, playback speed, and view rotation.

Rebuild the library after adding or replacing source FBXs with:

```powershell
C:\Godot\Godot_v4.6.2-stable_win64_console.exe --headless --path . --audio-driver Dummy --script res://tools/PilotAnimationBaker.gd
```

The baker chooses the imported take that contains actual movement. Some Mixamo
FBXs also contain a longer static `Take 001`, which must not be selected merely
because it is longer. Arms are solved through the fixed-length
`c_shoulder -> arm -> forearm -> hand` control chains, using the approved
running clip as the visual reference; Mixamo joint translations are not copied
into the differently proportioned ARP limbs. Those solved transforms then drive
the separate `shoulder`, `arm_stretch`, `forearm_stretch`, and `forearm_twist`
bones that actually deform the sleeves. Hand rotation is transferred
separately.
The ARP finger rig is not a one-to-one match for Mixamo, so the shared clips
keep the pilot's neutral finger pose rather than baking partial finger chains
that tear the glove mesh. Regenerating the library overwrites edits made
directly to the generated `.tres`.
The baker also corrects only the `piloting` clip's excessive forward head nod:
motion above 8 degrees is compressed and capped at 12 degrees. Keep this in the
baker rather than hand-editing the generated head track so future rebuilds
retain the correction.

`parachute` is the established exception: it retains the arm-routing behavior
used by the pose tuner and bakes the saved `parachute_pose_settings.tres`
values. It does not use the general gesture/locomotion arm solver.

`Tests/PilotAnimationLibrarySmoketest.gd` samples every clip at several times
and rejects any visible deformation-bone length or midpoint drift above 2 mm.

## Parachute pose tuning

Open `res://tools/PilotPoseTuner.tscn` and press F6. The tuner shows the real
pilot, can play or scrub the 4.7-second source clip, and exposes local X/Y/Z
offsets for each shoulder/clavicle, upper arm, forearm, and hand.
`Reset to raw clip` zeros every offset. `Save pose` writes the result to
`parachute_pose_settings.tres`, which is the same resource used by gameplay.
Use `Mirror left -> right` or
`Mirror right -> left` to reflect a finished arm through the rig's actual bone
rest frames; copying numeric rotations directly does not work because the two
sides use different local axes.

Unused historical pilot meshes and pose experiments are kept in `../archive`, which has a `.gdignore` file so Godot cannot accidentally import or offer them as live project assets.
