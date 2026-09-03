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

`animations/officer_idle_animation_library.tres` contains the five additional
looping bridge-officer idles as `officer/idle_3` through `officer/idle_7` when
mounted beside the shared library on the officer's `AnimationPlayer`. Keeping
them officer-only avoids binding those long clips on every pooled cockpit pilot.

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
because it is longer. Except for the separately preserved `run`, arms are solved
through the fixed-length `c_shoulder -> arm -> forearm -> hand` control chains;
Mixamo joint translations are not copied into the differently proportioned ARP
limbs. Those solved transforms then drive
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
`walk`, `run`, `turn_left`, and `turn_right` are baked in place. DownedPilot
moves and rotates the character root itself, avoiding doubled travel and the
visible snap that imported Mixamo root motion would cause when a loop wraps.
The general retargeter solves both arms and legs as fixed-length joint chains.
ARP's calf deformation bones and FK feet belong to separate hierarchy branches,
so feet are explicitly anchored to the solved ankles instead of receiving an
independent Mixamo translation. Hands and feet take their direction and roll
from their terminal source segments rather than copying incompatible global
Mixamo rotations. `run` is a deliberate exception: its complete, previously
approved bake is stored in `animations/approved_run_animation.tres`. The baker
copies that reference unchanged except for removing horizontal root travel. It
does not attempt to recreate the pose with a special retarget solver; that
approach produced visibly different arm and hand motion. The reference was
recovered from the pre-retarget-change library in commit `ab7633b`. `piloting`
remains the approved seated reference.

`PilotAnimationLibrarySmoketest.gd` checks the hierarchical arm chain and the
visible knee/ankle chain at multiple samples. It compares every key of `run`
against the approved reference, because generic anatomical limits did not catch
the visually broken rebake. `PilotArmMotionPreview.gd` renders at a three-quarter
angle because a front view can hide depth-axis stretching.

## Gameplay animation states

- Cockpit: looping `piloting`.
- Seat separation and canopy descent: looping `parachute`, started at physical
  seat release and not restarted when the canopy opens.
- Ground movement: `walk` below 4.6 m/s and `run` at or above it.
- Large heading changes while stationary: `turn_left` or `turn_right`; movement
  resumes with the normal walk/run clip once aligned.
- Waiting for rescue: `idle_breathing`.
- Friendly helicopter within 1 km: turn to face it, wave once when noticed, and
  repeat `wave` about every 10 seconds while it remains nearby.

The carrier-deck animation reviewer keeps its outer node at one fixed position.
It supplies the same 90-degree visible-root rotation that gameplay supplies for
the turn clips, preserves authored looping versus one-shot playback, and retains
the death clip's internal forward root travel so the fall does not stretch in
place or snap-repeat.

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
